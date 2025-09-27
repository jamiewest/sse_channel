import 'package:sse_channel/sse_channel.dart';

void main() {
  final channel = SseChannel.connect(
    Uri.parse('https://sse.dev/test?interval=10'),
  );

  channel.stream.listen((event) {
    print('[${event.event}] ${event.data}');
  });

  channel.sink.add('Test');
}
