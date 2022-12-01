# sse_channel

The `web_socket_channel` package provides [`StreamChannel`][stream_channel]
wrappers for WebSocket connections. 

[stream_channel]: https://pub.dev/packages/stream_channel

```dart
import 'package:sse_channel/sse_channel.dart';

void main() {
  final channel =
      SseChannel.connect(Uri.parse('http://127.0.0.1:8080/sseHandler'));

  channel.stream.listen((message) {
    print(message);
  });

  channel.sink.add('test');
}
```