class SseClientException implements Exception {
  final String message;

  const SseClientException(this.message);

  @override
  String toString() {
    return message;
  }
}
