# sse_channel

`sse_channel` wraps Server-Sent Events (SSE) endpoints with the [`StreamChannel`][stream_channel]
API so you can treat bi-directional SSE as a first-class stream/sink pair on both
`dart:io` and `dart:html`.

[stream_channel]: https://pub.dev/packages/stream_channel

## Quick start

```dart
import 'dart:convert';

import 'package:sse_channel/sse_channel.dart';

void main() {
  final channel = SseChannel.connect(Uri.parse('https://sse.dev/test'));

  channel.stream.listen(
    (event) {
      print('[${event.event}] ${event.data} (id: ${event.id})');
    },
    onError: (error, stackTrace) {
      if (error is SseChannelException) {
        print('SSE failure: ${error.message}');
      }
    },
  );

  channel.sink.add(jsonEncode({'type': 'ping'}));
}
```

## Why use it?

- **Spec-aligned client.** The IO implementation tracks `Last-Event-ID`, honors
  `retry:` hints, sets `Cache-Control: no-cache`, and reconnects automatically
  using the WHATWG SSE rules.
- **Rich events.** Streams emit `Event` instances so you retain the payload,
  event name, and identifier metadata that servers send.
- **Consistent errors.** Both IO and HTML channels surface failures via the same
  `SseChannelException` type, making it simple to detect connection issues.
- **Test friendly.** The HTML channel exposes `HtmlSseChannel.test`, and the IO
  implementation can be exercised with in-process servers; the repository ships
  with unit and integration tests you can mirror.

## Testing

Run the VM test suite (includes IO integration coverage):

```bash
$ dart test
```

Run browser tests (exercises the HTML channel using Chrome by default):

```bash
$ dart test -p chrome
```

Use `HtmlSseChannel.test` in your own applications to inject a mock stream and
sink when you need to verify browser-side code without a live SSE endpoint.

On the IO side you can now import `package:sse_channel/io.dart` and construct
`IOSseChannel` with your own `StreamChannel` to reuse the package's
reconnection logic while driving it with a fake transport during tests.

## Platform support

- `dart:io` – uses `package:http` to establish SSE connections and POST
  responses back to the server.
- `dart:html` – delegates to `package:sse` in the browser and adapts events to
  the shared `Event` model.

## Resources

- [Server-Sent Events specification (WHATWG HTML)](https://html.spec.whatwg.org/multipage/server-sent-events.html)
- [StreamChannel API docs](https://pub.dev/documentation/stream_channel/latest/)
