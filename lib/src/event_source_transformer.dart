import 'dart:async';
import 'dart:convert';

import 'exception.dart';

typedef RetryIndicator = void Function(Duration retry);

class EventSourceTransformer implements StreamTransformer<List<int>, Event> {
  EventSourceTransformer({this.retryIndicator});

  final RetryIndicator? retryIndicator;

  @override
  Stream<Event> bind(Stream<List<int>> stream) {
    late StreamSubscription<String> subscription;
    late StreamController<Event> controller;

    controller = StreamController<Event>(
      onListen: () {
        var currentEvent = Event();
        String? lastEventId;
        final lineRegex = RegExp(r'^([^:]*)(?::)?(?: )?(.*)?$');
        // This stream will receive chunks of data that are not necessarily a
        // single event. We build events on the fly and emit them when we
        // encounter a blank line, then start fresh for the next event.
        subscription = stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            .listen(
          (String line) {
            if (line.isEmpty) {
              _dispatchCurrentEvent(controller, currentEvent, lastEventId);
              currentEvent = Event();
              return;
            }

            final Match match = lineRegex.firstMatch(line)!;
            final field = match.group(1)!;
            final value = match.group(2) ?? '';

            if (field.isEmpty) {
              return;
            }

            switch (field) {
              case 'event':
                currentEvent.event = value;
                break;
              case 'data':
                currentEvent.data = '${currentEvent.data ?? ''}$value\n';
                break;
              case 'id':
                if (!value.contains('\u0000')) {
                  lastEventId = value;
                  currentEvent.id = lastEventId;
                }
                break;
              case 'retry':
                final parsed = int.tryParse(value);
                if (parsed != null && parsed >= 0 && retryIndicator != null) {
                  retryIndicator!(Duration(milliseconds: parsed));
                }
                break;
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(
              error is SseChannelException
                  ? error
                  : SseChannelException.from(error),
              stackTrace,
            );
          },
          onDone: () {
            _dispatchCurrentEvent(controller, currentEvent, lastEventId);
            controller.close();
          },
        );
      },
      onCancel: () => subscription.cancel(),
    );

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<List<int>, Event, RS, RT>(this);
}

class Event implements Comparable<Event> {
  Event({this.id, this.event, this.data});

  Event.message({this.id, this.data}) : event = 'message';

  /// An identifier that can be used to allow a client to replay
  /// missed Events by returning the Last-Event-Id header.
  /// Return empty string if not required.
  String? id;

  /// The name of the event. Return empty string if not required.
  String? event;

  /// The payload of the event.
  String? data;

  @override
  int compareTo(Event other) => id!.compareTo(other.id!);
}

void _dispatchCurrentEvent(
  StreamController<Event> controller,
  Event currentEvent,
  String? lastEventId,
) {
  final data = currentEvent.data;
  if (data == null) {
    return;
  }

  if (data.isNotEmpty && data.endsWith('\n')) {
    currentEvent.data = data.substring(0, data.length - 1);
  }

  currentEvent.event =
      (currentEvent.event == null || currentEvent.event!.isEmpty)
          ? 'message'
          : currentEvent.event;

  currentEvent.id ??= lastEventId;
  controller.add(currentEvent);
}
