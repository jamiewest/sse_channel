import 'dart:async';
import 'dart:convert';

import 'package:sse_channel/sse_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SseTransformer', () {
    test('parses basic data event and defaults to message type', () async {
      final stream = Stream<List<int>>.fromIterable([
        utf8.encode('data: hello world\n\n'),
      ]);

      final events = await stream.transform(SseTransformer()).toList();

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.event, equals('message'));
      expect(event.data, equals('hello world'));
      expect(event.id, isNull);
    });

    test('preserves multi-line data blocks', () async {
      final buffer = StringBuffer()
        ..writeln('data: line one')
        ..writeln('data: line two')
        ..writeln();
      final stream = Stream<List<int>>.fromIterable([
        utf8.encode(buffer.toString()),
      ]);

      final events = await stream.transform(SseTransformer()).toList();

      expect(events, hasLength(1));
      expect(events.first.data, equals('line one\nline two'));
    });

    test('captures event type and id metadata', () async {
      final buffer = StringBuffer()
        ..writeln('event: custom')
        ..writeln('id: 42')
        ..writeln('data: payload')
        ..writeln();
      final stream = Stream<List<int>>.fromIterable([
        utf8.encode(buffer.toString()),
      ]);

      final events = await stream.transform(SseTransformer()).toList();

      final event = events.single;
      expect(event.event, equals('custom'));
      expect(event.id, equals('42'));
      expect(event.data, equals('payload'));
    });

    test('reuses last event id when field omitted', () async {
      final buffer = StringBuffer()
        ..writeln('id: 5')
        ..writeln('data: first')
        ..writeln()
        ..writeln('data: second')
        ..writeln();

      final events = await Stream<List<int>>.fromIterable([
        utf8.encode(buffer.toString()),
      ]).transform(SseTransformer()).toList();

      expect(events, hasLength(2));
      expect(events[0].id, equals('5'));
      expect(events[1].id, equals('5'));
    });

    test('ignores ids containing null characters', () async {
      final payload = StringBuffer()
        ..writeln('id: valid')
        ..writeln('data: first')
        ..writeln()
        ..writeln('id: bad${String.fromCharCode(0)}id')
        ..writeln('data: second')
        ..writeln();

      final events = await Stream<List<int>>.fromIterable([
        utf8.encode(payload.toString()),
      ]).transform(SseTransformer()).toList();

      expect(events, hasLength(2));
      expect(events[0].id, equals('valid'));
      expect(events[1].id, equals('valid'));
    });

    test('invokes retry indicator when retry field provided', () async {
      Duration? retry;
      final transformer = SseTransformer(
        retryIndicator: (value) => retry = value,
      );

      final buffer = StringBuffer()
        ..writeln('retry: 5000')
        ..writeln('data: retry test')
        ..writeln();

      final events = await Stream<List<int>>.fromIterable([
        utf8.encode(buffer.toString()),
      ]).transform(transformer).toList();

      expect(events, hasLength(1));
      expect(retry, equals(const Duration(milliseconds: 5000)));
    });

    test(
      'dispatches final event when stream closes without blank line',
      () async {
        final stream = Stream<List<int>>.fromIterable([
          utf8.encode('data: trailing'),
        ]);

        final events = await stream.transform(SseTransformer()).toList();

        expect(events, hasLength(1));
        expect(events.single.data, equals('trailing'));
      },
    );

    test('wraps transformer errors in SseChannelException', () async {
      final controller = StreamController<List<int>>();
      final transformed = controller.stream.transform(SseTransformer());
      final received = <MessageEvent>[];
      final completer = Completer<void>();
      Object? error;

      transformed.listen(
        received.add,
        onError: (Object err, StackTrace stackTrace) {
          error = err;
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      controller.add(utf8.encode('data: hello\n\n'));
      controller.addError(Exception('boom'));
      await controller.close();
      await completer.future;

      expect(received, hasLength(1));
      expect(received.single.data, equals('hello'));
      expect(error, isA<SseChannelException>());
    });
  });
}
