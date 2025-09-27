import 'package:sse_channel/sse_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SseChannelException', () {
    test('stores optional message', () {
      final exception = SseChannelException('failure');

      expect(exception.message, equals('failure'));
      expect(exception.inner, isNull);
      expect(exception.toString(), contains('failure'));
    });

    test('wraps inner exception', () {
      final inner = ArgumentError('bad');
      final exception = SseChannelException.from(inner);

      expect(exception.inner, same(inner));
      expect(exception.message, equals(inner.toString()));
    });

    test('toString falls back to type name without message', () {
      final exception = SseChannelException();

      expect(exception.toString(), equals('SseChannelException'));
    });
  });
}
