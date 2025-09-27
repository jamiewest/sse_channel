## 0.2.1

- Added an injectable `IOSseChannel(StreamChannel channel)` constructor so IO
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
