/// An exception thrown by a [SseChannel].
class SseChannelException implements Exception {
  final String? message;

  /// The exception that caused this one, if available.
  final Object? inner;

  SseChannelException([this.message]) : inner = null;

  SseChannelException.from(this.inner) : message = inner.toString();

  @override
  String toString() =>
      message == null ? 'SseChannelException' : 'SseChannelException: $message';
}
