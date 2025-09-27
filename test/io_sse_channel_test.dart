@TestOn('vm')

import 'dart:async';
import 'dart:io';

import 'package:sse_channel/sse_channel.dart';
import 'package:test/test.dart';

void main() {
  group('IOSseChannel integration', () {
    late HttpServer server;
    late Uri serverUri;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverUri = Uri.parse('http://${server.address.host}:${server.port}/stream');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('reconnects using Last-Event-ID when server closes connection', () async {
      final lastEventHeaders = <String?>[];
      final secondRequest = Completer<void>();

      unawaited(_serveSequence(server, lastEventHeaders, secondRequest));

      final channel = SseChannel.connect(serverUri);
      final eventsFuture = channel.stream.take(2).toList();

      final events = await eventsFuture.timeout(const Duration(seconds: 2));
      await secondRequest.future.timeout(const Duration(seconds: 2));

      expect(events.map((event) => event.data), ['first', 'second']);
      expect(lastEventHeaders.length, greaterThanOrEqualTo(2));
      expect(lastEventHeaders.first, isNull);
      expect(lastEventHeaders.last, equals('1'));

      await channel.sink.close();
    });
  });
}

Future<void> _serveSequence(
  HttpServer server,
  List<String?> lastEventHeaders,
  Completer<void> secondRequest,
) async {
  var requestCount = 0;

  await for (final request in server) {
    lastEventHeaders.add(request.headers.value('last-event-id'));

    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('text', 'event-stream');
    response.headers.set('Cache-Control', 'no-cache');

    if (requestCount == 0) {
      response
        ..write('id: 1\n')
        ..write('retry: 10\n')
        ..write('data: first\n\n');
      await response.flush();
      unawaited(Future<void>.delayed(const Duration(milliseconds: 20), () async {
        await response.close();
      }));
    } else {
      response.write('data: second\n\n');
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await response.close();
      if (!secondRequest.isCompleted) {
        secondRequest.complete();
      }
      break;
    }

    requestCount++;
  }
}
