import 'package:stream_channel/stream_channel.dart';

// ignore: uri_does_not_exist
import '_connect_api.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) '_connect_html.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) '_connect_io.dart' as platform;

abstract class SseChannel extends StreamChannelMixin {
  factory SseChannel.connect(Uri url) => platform.connect(url);
}
