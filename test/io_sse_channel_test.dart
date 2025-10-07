@TestOn('vm')
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sse_channel/sse_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SseChannel integration', () {
    late HttpServer server;
    late Uri serverUri;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverUri = Uri.parse(
        'http://${server.address.host}:${server.port}/stream',
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test(
      'reconnects using Last-Event-ID when server closes connection',
      () async {
        final lastEventHeaders = <String?>[];
        final secondRequest = Completer<void>();

        unawaited(_serveSequence(server, lastEventHeaders, secondRequest));

        final channel = SseChannel.connect(serverUri);
        final messagesFuture = channel.stream
            .take(2)
            .map((event) => event.data)
            .toList();

        final messages = await messagesFuture.timeout(
          const Duration(seconds: 2),
        );
        await secondRequest.future.timeout(const Duration(seconds: 2));

        expect(messages, ['first', 'second']);
        expect(lastEventHeaders.length, greaterThanOrEqualTo(2));
        expect(lastEventHeaders.first, isNull);
        expect(lastEventHeaders.last, equals('1'));

        await channel.sink.close();
      },
    );

    test('sends pending outgoing messages before closing', () async {
      final postedMessages = <String>[];
      final postsComplete = Completer<void>();

      unawaited(
        _serveCloseSequence(server, postedMessages, postsComplete),
      );

      final channel = SseChannel.connect(serverUri);
      final closeDone = Completer<void>();

      channel.stream.listen((_) {
        channel.sink.add('received!');
        channel.sink.close().then((_) {
          if (!closeDone.isCompleted) {
            closeDone.complete();
          }
        });
      });

      await channel.ready.timeout(const Duration(seconds: 2));
      await postsComplete.future.timeout(const Duration(seconds: 2));
      await closeDone.future.timeout(const Duration(seconds: 2));

      expect(postedMessages, ['0:"received!"', '1:"close"']);
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
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 20), () async {
          await response.close();
        }),
      );
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

Future<void> _serveCloseSequence(
  HttpServer server,
  List<String> postedMessages,
  Completer<void> postsComplete,
) async {
  await for (final request in server) {
    if (request.method == 'GET') {
      final response = request.response;
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType('text', 'event-stream');
      response.headers.set('Cache-Control', 'no-cache');
      response.write('data: hello\n\n');
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await response.close();
      continue;
    }

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      continue;
    }

    final body = await utf8.decoder.bind(request).join();
    final messageId = request.uri.queryParameters['messageId'];
    postedMessages.add('${messageId ?? 'missing'}:$body');

    request.response.statusCode = HttpStatus.ok;
    await request.response.close();

    if (postedMessages.length >= 2 && !postsComplete.isCompleted) {
      postsComplete.complete();
    }
  }
}
