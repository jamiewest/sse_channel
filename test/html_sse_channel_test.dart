@TestOn('browser')
import 'dart:async';

import 'package:sse_channel/sse_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SseChannel', () {
    late StreamController<String?> incoming;
    late StreamController<String?> outgoing;
    late List<String?> sentMessages;
    late List<MessageEvent> receivedEvents;
    late SseChannel channel;
    late Completer<void> closed;

    setUp(() {
      incoming = StreamController<String?>.broadcast();
      outgoing = StreamController<String?>.broadcast();
      sentMessages = <String?>[];
      receivedEvents = <MessageEvent>[];
      closed = Completer<void>();

      outgoing.stream.listen(sentMessages.add);

      channel = SseChannel(StreamChannel(incoming.stream, outgoing.sink));

      channel.stream.listen(receivedEvents.add);
    });

    tearDown(() async {
      await incoming.close();
      await outgoing.close();
    });

    test('forwards incoming messages as Events', () async {
      incoming.add('payload');
      await Future<void>.delayed(Duration.zero);

      expect(receivedEvents, hasLength(1));
      expect(receivedEvents.single.data, equals('payload'));
      expect(receivedEvents.single.event, equals('message'));
    });

    test('writes outgoing messages to provided sink', () async {
      channel.sink.add('to-server');
      await Future<void>.delayed(Duration.zero);

      expect(sentMessages, equals(['to-server']));
    });

    test('closing stream cancels subscription and triggers onClose', () async {
      await channel.sink.close();
      await closed.future.timeout(const Duration(seconds: 1));
    });
  });
}
