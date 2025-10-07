## 0.2.2

- Ensure `SseSink.close` waits for pending outgoing messages so the final payload
  reaches the server before the connection shuts down.
- Serialize IO POST requests to preserve outbound message ordering and avoid
  race conditions when multiple sends happen back-to-back.
- Unified the implementation into a single `SseChannel` that runs on both VM and
  web platforms, removing the old IO/HTML split.
- Document the need to await `SseChannel.ready` in the README quick start and
  expand integration coverage for the close-after-send flow.

## 0.2.1

- Added an injectable `IOSseChannel(StreamChannel<String?> channel)` constructor so IO
  clients can supply their own transport (useful for tests or custom proxies)
  while still reusing the package's reconnection and error handling.
- Relaxed IO client disposal to play nicely with externally managed HTTP
  clients when the channel is torn down.

## 0.2.0

- **Breaking:** `SseChannel.stream` now emits `Event` objects exposing `data`, `event`, and
  `id` metadata rather than raw strings.
- Improved IO client compliance with the WHATWG SSE spec: preserves `Last-Event-ID`,
  honors `retry:` hints, sends `Cache-Control: no-cache`, and retries automatically.
- Surface connection and send failures as `SseChannelException` for both IO and HTML
  implementations and re-export the type for package users.
- Added `HtmlSseChannel.test` to make browser-specific code testable without a real
  network connection.
- Expanded test coverage with extensive unit tests for the event transformer, IO
  reconnect flow, and browser behaviour.

## 0.1.1

- Update packages.

## 0.0.3

- Fix README.

## 0.0.2

- Update README and example, updates.

## 0.0.1

- Initial version.
