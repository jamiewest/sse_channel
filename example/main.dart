import 'package:sse_channel/sse_channel.dart';

Future<void> main() async {
  final url = Uri.parse('http://localhost:8080/sse');
  final channel = SseChannel.connect(url);

  await channel.ready;

  channel.stream.listen((message) {
    channel.sink.add('received!');
    channel.sink.close(1, "close reason");
  });
}
