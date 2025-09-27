import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:uuid/uuid.dart';

// Limits concurrent outbound HTTP requests so servers aren't flooded.
final _requestPool = Pool(1000);

/// IO-backed implementation of [SseChannel] that communicates with an SSE
/// endpoint using `package:http`.
class IOSseChannel extends StreamChannelMixin implements SseChannel {
  int _lastMessageId = -1;
  final Uri _serverUrl;
  final String _clientId;
  final http.Client _client;
  StreamSubscription<Event>? _incomingSubscription;
  StreamSubscription<String?>? _outgoingSubscription;
  late final StreamController<Event> _incomingController;
  late final StreamController<String?> _outgoingController;
  final _onConnected = Completer();
  bool _incomingClosed = false;
  bool _disposed = false;
  bool _shouldReconnect = true;
  String? _lastEventId;
  Duration _retryDelay = const Duration(milliseconds: 3000);
  Timer? _reconnectTimer;

  IOSseChannel._(Uri serverUrl)
    : _serverUrl = serverUrl,
      _client = http.Client(),
      _clientId = Uuid().v4(),
      _outgoingController = StreamController<String?>() {
    _incomingController = StreamController<Event>.broadcast(
      onListen: _startListening,
      onCancel: () async {
        _shouldReconnect = false;
        _reconnectTimer?.cancel();
        await _closeIncomingController();
        await _disposeResources();
      },
    );

    _onConnected.future.then<void>(
      (_) {
        _outgoingSubscription = _outgoingController.stream.listen(
          _onOutgoingMessage,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _outgoingController.addError(error, stackTrace);
        _outgoingController.close();
      },
    );
  }

  factory IOSseChannel.connect(Uri url) {
    return IOSseChannel._(url);
  }

  @override
  StreamSink<String?> get sink => _outgoingController.sink;

  @override
  Stream<Event> get stream => _incomingController.stream;

  Future<void> _onOutgoingMessage(String? message) async {
    await _requestPool.withResource(() async {
      try {
        final encodedMessage = jsonEncode(message);
        final url =
            '$_serverUrl?sseClientId=$_clientId&messageId=${++_lastMessageId}';
        await http.post(Uri.parse(url), body: encodedMessage);
      } on Object catch (error, stackTrace) {
        _notifySendError(error, stackTrace);
      }
    });
  }

  void _notifySendError(Object error, StackTrace stackTrace) {
    _emitError(error, stackTrace);
  }

  // Establishes the SSE connection and forwards events to the incoming stream.
  void _startListening() {
    _shouldReconnect = true;
    _connectToServer();
  }

  Future<void> _connectToServer() async {
    if (_incomingClosed || _disposed) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final request =
        http.Request(
            'GET',
            _serverUrl.replace(queryParameters: {'sseClientId': _clientId}),
          )
          ..headers['Accept'] = 'text/event-stream'
          ..headers['Cache-Control'] = 'no-cache';

    if (_lastEventId != null) {
      request.headers['Last-Event-ID'] = _lastEventId!;
    }

    try {
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        final error = SseChannelException(
          'Failed to connect to $_serverUrl (status ${response.statusCode})',
        );
        _emitError(error, StackTrace.current);
        _completeWithError(error);
        _scheduleReconnect();
        return;
      }

      await _incomingSubscription?.cancel();
      _incomingSubscription = response.stream
          .transform(EventSourceTransformer(retryIndicator: _updateRetry))
          .listen(
            (event) {
              if (_incomingClosed) {
                return;
              }
              if (event.id != null) {
                _lastEventId = event.id;
              }
              _incomingController.add(event);
            },
            onError: (Object error, StackTrace stackTrace) {
              _emitError(error, stackTrace);
              _scheduleReconnect();
            },
            onDone: () {
              _incomingSubscription = null;
              _scheduleReconnect();
            },
            cancelOnError: false,
          );

      if (!_onConnected.isCompleted) {
        _onConnected.complete();
      }
    } catch (error, stackTrace) {
      _emitError(error, stackTrace);
      _completeWithError(error, stackTrace);
      _scheduleReconnect();
    }
  }

  Future<void> _closeIncomingController() async {
    if (_incomingClosed) {
      return;
    }
    _incomingClosed = true;
    await _incomingController.close();
  }

  // Cancels any remaining subscriptions and closes the HTTP client exactly once.
  Future<void> _disposeResources() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _shouldReconnect = false;
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _outgoingSubscription?.cancel();
    _outgoingSubscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _client.close();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _incomingClosed || _disposed) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_retryDelay, _connectToServer);
  }

  void _updateRetry(Duration retry) {
    if (retry.isNegative) {
      return;
    }
    _retryDelay = retry;
  }

  void _emitError(Object error, [StackTrace? stackTrace]) {
    if (_incomingClosed) {
      return;
    }
    _incomingController.addError(_asSseException(error), stackTrace);
  }

  void _completeWithError(Object error, [StackTrace? stackTrace]) {
    if (_onConnected.isCompleted) {
      return;
    }
    _onConnected.completeError(_asSseException(error), stackTrace);
  }

  SseChannelException _asSseException(Object error) {
    return error is SseChannelException
        ? error
        : SseChannelException.from(error);
  }
}
