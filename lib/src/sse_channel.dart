import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:stream_channel/stream_channel.dart';

import '../../src/util.dart';

typedef RetryIndicator = void Function(Duration retry);

/// Limit for the number of concurrent outgoing requests.
///
/// Chrome drops outgoing requests on the floor after some threshold. To prevent
/// these errors we buffer outgoing requests with a pool.
///
/// Note Chrome's limit is 6000. So this gives us plenty of headroom.
final _requestPool = Pool(1000);

/// IO-backed implementation of [SseChannel] that communicates with an SSE
/// endpoint using `package:http`.
class SseChannel extends StreamChannelMixin {
  final String _clientId;

  final _incomingController = StreamController<MessageEvent>();

  final _outgoingController = StreamController<String?>();

  late final SseSink _sink = SseSinkImpl(_outgoingController.sink);

  final _logger = Logger('SseChannel');

  final _onConnected = Completer<void>();

  int _lastMessageId = -1;

  late final Uri? _serverUrl;

  Timer? _errorTimer;

  Timer? _reconnectTimer;

  http.Client? _client;

  StreamSubscription<String?>? _outgoingSubscription;

  StreamSubscription<MessageEvent>? _incomingSubscription;

  Future<void> _pendingOutgoing = Future<void>.value();

  Duration _retryDuration = const Duration(milliseconds: 3000);

  String? _lastEventId;

  bool _isClosed = false;

  Object? _lastError;

  SseChannel(
    StreamChannel<String?> channel, {
    String? debugKey,
    http.BaseClient? client,
  }) : _clientId = debugKey == null
           ? generateId()
           : '$debugKey-${generateId()}' {
    _client = client ?? http.Client();

    unawaited(
      _onConnected.future
          .then((_) {
            if (_isClosed) {
              return;
            }
            _outgoingSubscription = channel.stream.listen(
              _onOutgoingMessage,
              onDone: _onOutgoingDone,
              onError: (Object error, StackTrace _) {
                if (_isClosed) {
                  return;
                }
                _logger.warning('[$_clientId] Outgoing stream error: $error');
              },
            );
          })
          .catchError((Object _, StackTrace __) {
            // Connection attempt failed and has already been surfaced elsewhere.
          }),
    );
  }

  /// [serverUrl] is the URL under which the server is listening for
  /// incoming bi-directional SSE connections. [debugKey] is an optional key
  /// that can be used to identify the SSE connection.
  SseChannel.connect(
    Object serverUrl, {
    String? debugKey,
    http.BaseClient? client,
  }) : _clientId = debugKey == null
           ? generateId()
           : '$debugKey-${generateId()}' {
    _serverUrl = Uri.parse('$serverUrl?sseClientId=$_clientId');
    _client = client ?? http.Client();

    unawaited(
      _onConnected.future
          .then((_) {
            if (_isClosed) {
              return;
            }
            _outgoingSubscription = _outgoingController.stream.listen(
              _onOutgoingMessage,
              onDone: _onOutgoingDone,
              onError: (Object error, StackTrace _) {
                if (_isClosed) {
                  return;
                }
                _logger.warning('[$_clientId] Outgoing stream error: $error');
              },
            );
          })
          .catchError((Object _, StackTrace __) {
            // Connection attempt failed and has already been surfaced elsewhere.
          }),
    );

    _connect();
  }

  Future<void> get ready => _onConnected.future;

  /// Add messages to this [StreamSink] to send them to the server.
  ///
  /// The message added to the sink has to be JSON encodable. Messages that fail
  /// to encode will be logged through a [Logger].
  @override
  SseSink get sink => _sink;

  /// [Stream] of messages sent from the server to this client.
  ///
  /// A message is a decoded JSON object.
  @override
  Stream<MessageEvent> get stream => _incomingController.stream;

  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;

    _cancelErrorTimer();

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _incomingSubscription?.cancel();
    _incomingSubscription = null;

    _outgoingSubscription?.cancel();
    _outgoingSubscription = null;

    _client?.close();
    _client = null;

    // If the initial connection was never established we need to attach a
    // listener so closing the controller completes the sink future.
    if (!_onConnected.isCompleted && _outgoingSubscription == null) {
      _outgoingController.stream.drain<void>();
    }

    if (!_incomingController.isClosed) {
      _incomingController.close();
    }
    if (!_outgoingController.isClosed) {
      _outgoingController.close();
    }
  }

  void _closeWithError(Object error) {
    if (!_incomingController.isClosed) {
      _incomingController.addError(error);
    }
    close();
    if (!_onConnected.isCompleted) {
      // This call must happen after the call to close() which checks
      // whether the completer was completed earlier.
      _onConnected.completeError(error);
    }
  }

  void _connect() {
    if (_isClosed) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_openEventStream());
  }

  Future<void> _openEventStream() async {
    if (_isClosed) {
      return;
    }

    final client = _client ?? http.Client();
    _client ??= client;

    final request = http.Request('GET', _serverUrl!)
      ..headers[HttpHeaders.accept] = 'text/event-stream'
      ..headers[HttpHeaders.cacheControl] = 'no-cache';
    if (HttpHeaders.isBrowserSettable(HttpHeaders.connection)) {
      // Fetch forbids `connection`; guard so BrowserClient stays happy.
      request.headers[HttpHeaders.connection] = 'keep-alive';
    }
    final lastEventId = _lastEventId;
    if (lastEventId != null) {
      request.headers['Last-Event-ID'] = lastEventId;
    }

    try {
      final response = await client.send(request);

      if (_isClosed) {
        await response.stream.drain<void>();
        return;
      }

      if (response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.resetContent) {
        close();
        return;
      }

      if (response.statusCode != HttpStatus.ok) {
        final exception = SseChannelException(
          '[$_clientId] Unexpected status ${response.statusCode} '
          'connecting to $_serverUrl',
        );
        _logger.warning(exception.toString());
        _startErrorTimer(exception);
        _scheduleReconnect();
        return;
      }

      final contentType = response.headers['content-type'];
      if (contentType == null ||
          !contentType.toLowerCase().startsWith('text/event-stream')) {
        final exception = SseChannelException(
          '[$_clientId] Invalid content-type "$contentType" '
          'from $_serverUrl',
        );
        _logger.warning(exception.toString());
        _startErrorTimer(exception);
        _scheduleReconnect();
        return;
      }

      _cancelErrorTimer();

      if (!_onConnected.isCompleted) {
        _onConnected.complete();
      }

      await _incomingSubscription?.cancel();
      _incomingSubscription = response.stream
          .transform(SseTransformer(retryIndicator: _updateRetry))
          .listen(
            (event) {
              if (_isClosed) {
                return;
              }
              _dispatchEvent(event);
            },
            onError: (Object error, StackTrace _) {
              if (_isClosed) {
                return;
              }
              final wrapped = error is SseChannelException
                  ? error
                  : SseChannelException.from(error);
              _logger.warning('[$_clientId] SSE stream error: $wrapped');
              _startErrorTimer(wrapped);
              _scheduleReconnect();
            },
            onDone: () {
              if (_isClosed) {
                return;
              }
              final exception = SseChannelException(
                '[$_clientId] SSE stream closed unexpectedly',
              );
              _logger.info(exception.toString());
              _startErrorTimer(exception);
              _scheduleReconnect();
            },
            cancelOnError: true,
          );
    } catch (error, _) {
      if (_isClosed) {
        return;
      }
      final wrapped = error is SseChannelException
          ? error
          : SseChannelException.from(error);
      _logger.warning('[$_clientId] SSE connection error: $wrapped');
      _startErrorTimer(wrapped);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect([Duration? delay]) {
    if (_isClosed) {
      return;
    }
    final wait = delay ?? _retryDuration;
    if (wait.isNegative) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(wait, () {
      _reconnectTimer = null;
      if (_isClosed) {
        return;
      }
      _connect();
    });
  }

  void _startErrorTimer(Object error) {
    if (_isClosed) {
      return;
    }
    _lastError = error;
    if (_errorTimer?.isActive ?? false) {
      return;
    }
    _errorTimer = Timer(const Duration(seconds: 5), () {
      if (_isClosed) {
        return;
      }
      final pendingError = _lastError ?? error;
      _closeWithError(pendingError);
    });
  }

  void _cancelErrorTimer() {
    _errorTimer?.cancel();
    _errorTimer = null;
    _lastError = null;
  }

  void _updateRetry(Duration retry) {
    if (retry.isNegative) {
      return;
    }
    _retryDuration = retry;
  }

  void _dispatchEvent(MessageEvent event) {
    final eventId = event.id;
    if (eventId != null) {
      _lastEventId = eventId;
    }
    switch (event.event) {
      case 'control':
        _onIncomingControlMessage(event);
      default:
        _onIncomingMessage(event);
        break;
    }
  }

  void _onIncomingControlMessage(MessageEvent message) {
    var data = message.data;
    if (data == 'close') {
      close();
    } else {
      throw UnsupportedError('[$_clientId] Illegal Control Message "$data"');
    }
  }

  void _onIncomingMessage(MessageEvent message) {
    //final payload = message.data;
    if (_incomingController.isClosed) {
      return;
    }
    _incomingController.add(message);
  }

  void _onOutgoingDone() {
    unawaited(_pendingOutgoing.whenComplete(close));
  }

  void _onOutgoingMessage(String? message) {
    _pendingOutgoing = _pendingOutgoing.then((_) => _sendOutgoing(message));
  }

  Future<void> _sendOutgoing(String? message) async {
    await _requestPool.withResource(() async {
      if (_isClosed) {
        return;
      }
      String? encodedMessage;
      try {
        encodedMessage = jsonEncode(message);
        // ignore: avoid_catching_errors
      } on JsonUnsupportedObjectError catch (e) {
        _logger.warning('[$_clientId] Unable to encode outgoing message: $e');
        // ignore: avoid_catching_errors
      } on ArgumentError catch (e) {
        _logger.warning('[$_clientId] Invalid argument: $e');
      }
      if (encodedMessage == null) {
        return;
      }
      try {
        final url = '$_serverUrl&messageId=${++_lastMessageId}';
        final uri = Uri.parse(url);
        final client = _client ??= http.Client();
        final response = await client.post(
          uri,
          headers: {'content-type': 'application/json'},
          body: encodedMessage,
        );
        if (response.statusCode >= HttpStatus.badRequest) {
          throw SseChannelException(
            '[$_clientId] Unexpected status ${response.statusCode} '
            'sending message to $uri',
          );
        }
      } catch (error) {
        final augmentedError =
            '[$_clientId] SSE client failed to send $message:\n $error';
        _logger.severe(augmentedError);
        _closeWithError(augmentedError);
      }
    });
  }
}

class SseSinkImpl extends DelegatingStreamSink<String?> implements SseSink {
  SseSinkImpl(super.delegate);

  @override
  Future close([int? closeCode, String? closeReason]) {
    // Queue the close control message after pending outgoing writes.
    add('close');
    return super.close();
  }
}

class MessageEvent implements Comparable<MessageEvent> {
  MessageEvent({this.id, this.event, this.data});

  MessageEvent.message({this.id, this.data}) : event = 'message';

  /// An identifier that can be used to allow a client to replay
  /// missed Events by returning the Last-Event-Id header.
  /// Return empty string if not required.
  String? id;

  /// The name of the event. Return empty string if not required.
  String? event;

  /// The payload of the event.
  String? data;

  @override
  int compareTo(MessageEvent other) => id!.compareTo(other.id!);
}

class SseTransformer implements StreamTransformer<List<int>, MessageEvent> {
  SseTransformer({this.retryIndicator});

  final RetryIndicator? retryIndicator;

  @override
  Stream<MessageEvent> bind(Stream<List<int>> stream) {
    late StreamSubscription<String> subscription;
    late StreamController<MessageEvent> controller;

    controller = StreamController<MessageEvent>(
      onListen: () {
        var currentEvent = MessageEvent();
        String? lastEventId;
        final lineRegex = RegExp(r'^([^:]*)(?::)?(?: )?(.*)?$');
        // This stream will receive chunks of data that are not necessarily a
        // single event. We build events on the fly and emit them when we
        // encounter a blank line, then start fresh for the next event.
        subscription = stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            .listen(
              (String line) {
                if (line.isEmpty) {
                  _dispatchCurrentEvent(controller, currentEvent, lastEventId);
                  currentEvent = MessageEvent();
                  return;
                }

                final Match match = lineRegex.firstMatch(line)!;
                final field = match.group(1)!;
                final value = match.group(2) ?? '';

                if (field.isEmpty) {
                  return;
                }

                switch (field) {
                  case 'event':
                    currentEvent.event = value;
                    break;
                  case 'data':
                    currentEvent.data = '${currentEvent.data ?? ''}$value\n';
                    break;
                  case 'id':
                    if (!value.contains('\u0000')) {
                      lastEventId = value;
                      currentEvent.id = lastEventId;
                    }
                    break;
                  case 'retry':
                    final parsed = int.tryParse(value);
                    if (parsed != null &&
                        parsed >= 0 &&
                        retryIndicator != null) {
                      retryIndicator!(Duration(milliseconds: parsed));
                    }
                    break;
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                controller.addError(
                  error is SseChannelException
                      ? error
                      : SseChannelException.from(error),
                  stackTrace,
                );
              },
              onDone: () {
                _dispatchCurrentEvent(controller, currentEvent, lastEventId);
                controller.close();
              },
            );
      },
      onCancel: () => subscription.cancel(),
    );

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<List<int>, MessageEvent, RS, RT>(this);
}

void _dispatchCurrentEvent(
  StreamController<MessageEvent> controller,
  MessageEvent currentEvent,
  String? lastEventId,
) {
  final data = currentEvent.data;
  if (data == null) {
    return;
  }

  if (data.isNotEmpty && data.endsWith('\n')) {
    currentEvent.data = data.substring(0, data.length - 1);
  }

  currentEvent.event =
      (currentEvent.event == null || currentEvent.event!.isEmpty)
      ? 'message'
      : currentEvent.event;

  currentEvent.id ??= lastEventId;
  controller.add(currentEvent);
}

/// The sink exposed by a [SseChannel].
///
/// This is like a normal [StreamSink], except that it supports extra arguments
/// to [close].
abstract interface class SseSink implements DelegatingStreamSink<String?> {
  /// Closes the SSE connection.
  ///
  /// [closeCode] and [closeReason] are the [close code][] and [reason][] sent
  /// to the remote peer, respectively. If they are omitted, the peer will see
  /// a "no status received" code with no reason.
  @override
  Future close([int? closeCode, String? closeReason]);
}
