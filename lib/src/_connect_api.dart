import 'channel.dart';
import 'exception.dart';

/// Creates a new Server Sent Events connection.
SseChannel connect(Uri url) {
  throw SseChannelException(
    'No implementation of the connect API provided for ${url.scheme} URLs.',
  );
}
