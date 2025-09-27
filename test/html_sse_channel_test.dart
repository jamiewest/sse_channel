@TestOn('browser')

import 'dart:async';

import 'package:sse_channel/html.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:test/test.dart';

void main() {
  group('HtmlSseChannel', () {
    late StreamController<String?> incoming;
    late StreamController<String?> outgoing;
    late List<String?> sentMessages;
    late List<Event> receivedEvents;
    late HtmlSseChannel channel;
    late Completer<void> closed;

    setUp(() {
      incoming = StreamController<String?>.broadcast();
      outgoing = StreamController<String?>.broadcast();
      sentMessages = <String?>[];
      receivedEvents = <Event>[];
      closed = Completer<void>();

      outgoing.stream.listen(sentMessages.add);

      channel = HtmlSseChannel.test(
        stream: incoming.stream,
        sink: outgoing.sink,
        onClose: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      );

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
