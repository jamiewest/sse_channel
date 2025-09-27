import 'dart:async';

import 'package:sse/client/sse_client.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:stream_channel/stream_channel.dart';

class HtmlSseChannel extends StreamChannelMixin implements SseChannel {
  HtmlSseChannel(SseClient client)
      : this._(
          client.stream,
          client.sink,
          client.close,
        );

  factory HtmlSseChannel.connect(Uri url) {
    return HtmlSseChannel(SseClient(url.toString()));
  }

  HtmlSseChannel.test({
    required Stream<String?> stream,
    required StreamSink<String?> sink,
    void Function()? onClose,
  }) : this._(stream, sink, onClose ?? () {});

  HtmlSseChannel._(
    Stream<String?> source,
    StreamSink<String?> target,
    void Function() onClose,
  )   : _source = source,
        _onClose = onClose,
        _sinkDelegate = target;

  final Stream<String?> _source;
  final StreamSink<String?> _sinkDelegate;
  final void Function() _onClose;
  StreamSubscription<String?>? _incomingSubscription;
  bool _closed = false;

  late final Stream<Event> _stream = Stream.multi((controller) {
    _incomingSubscription = _source.listen(
      (message) => controller.add(Event.message(data: message)),
      onError: (Object error, StackTrace stackTrace) {
        controller.addError(_asSseException(error), stackTrace);
      },
      onDone: () {
        controller.close();
        _close();
      },
    );

    controller.onCancel = () async {
      await _incomingSubscription?.cancel();
      _incomingSubscription = null;
      _close();
    };
  });

  late final StreamSink<String?> _sink =
      _CloseAwareSink(_sinkDelegate, _close);

  @override
  StreamSink<String?> get sink => _sink;

  @override
  Stream<Event> get stream => _stream;

  void _close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _incomingSubscription?.cancel();
    _incomingSubscription = null;
    _onClose();
  }

  SseChannelException _asSseException(Object error) {
    return error is SseChannelException
        ? error
        : SseChannelException.from(error);
  }
}

class _CloseAwareSink implements StreamSink<String?> {
  _CloseAwareSink(this._delegate, this._onClose);

  final StreamSink<String?> _delegate;
  final void Function() _onClose;
  bool _closed = false;

  @override
  void add(String? data) => _delegate.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _delegate.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<String?> stream) =>
      _delegate.addStream(stream);

  @override
  Future<void> close() async {
    if (_closed) {
      return _delegate.done;
    }
    _closed = true;
    await _delegate.close();
    _onClose();
  }

  @override
  Future<void> get done => _delegate.done;
}
