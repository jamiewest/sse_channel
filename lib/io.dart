import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';
import 'package:sse_channel/src/sse_client_exception.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:uuid/uuid.dart';

import 'src/event_source_transformer.dart';

final _requestPool = Pool(1000);

typedef OnConnected = void Function();

class IOSseChannel extends StreamChannelMixin implements SseChannel {
  int _lastMessageId = -1;
  final Uri _serverUrl;
  final String _clientId;
  late final StreamController<String?> _incomingController;
  late final StreamController<String?> _outgoingController;
  final _onConnected = Completer();
  late StreamSubscription incomingSubscription;
  late StreamSubscription outgoingSubscription;

  IOSseChannel._(
    Uri serverUrl,
  )   : _serverUrl = serverUrl,
        _clientId = Uuid().v4(),
        _outgoingController = StreamController<String?>() {
    final client = http.Client();

    final queryParameters = Map<String, String>.from(_serverUrl.queryParameters)
      ..addAll({'sseClientId': _clientId});

    _incomingController = StreamController<String?>.broadcast(
      onListen: () async {
        final request = http.Request(
          'GET',
          _serverUrl.replace(queryParameters: queryParameters),
        )..headers['Accept'] = 'text/event-stream';

        await client.send(request).then((response) {
          if (response.statusCode == 200) {
            incomingSubscription = response.stream
                .transform(EventSourceTransformer())
                .listen((event) => _incomingController.sink.add(event.data));

            _onConnected.complete();
          } else {
            _incomingController.addError(
              SseClientException('Failed to connect to $_serverUrl'),
            );
          }
        });
      },
      onCancel: () {
        incomingSubscription.cancel();
        _incomingController.close();

        outgoingSubscription.cancel();
        _outgoingController.close();
      },
    );

    _onConnected.future.whenComplete(
      () => outgoingSubscription =
          _outgoingController.stream.listen(_onOutgoingMessage),
    );
  }

  factory IOSseChannel.connect(Uri url) {
    return IOSseChannel._(
      url,
    );
  }

  @override
  StreamSink get sink => _outgoingController.sink;

  @override
  Stream get stream => _incomingController.stream;

  Future<void> _onOutgoingMessage(String? message) async {
    String? encodedMessage;

    await _requestPool.withResource(() async {
      try {
        encodedMessage = jsonEncode(message);
      } on JsonUnsupportedObjectError {
        //_logger.warning('[$_clientId] Unable to encode outgoing message: $e');
      } on ArgumentError {
        //_logger.warning('[$_clientId] Invalid argument: $e');
      }
      try {
        final queryParameters =
            Map<String, String>.from(_serverUrl.queryParameters)
              ..addAll({
                'sseClientId': _clientId,
                'messageId': '${_lastMessageId++}',
              });
        await http.post(
          _serverUrl.replace(queryParameters: queryParameters),
          body: encodedMessage,
        );
      } catch (error) {
        //final augmentedError =
        //    '[$_clientId] SSE client failed to send $message:\n $error';
        //_logger.severe(augmentedError);
        //_closeWithError(augmentedError);
      }
    });
  }
}
