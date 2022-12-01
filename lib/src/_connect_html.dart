import 'package:sse_channel/html.dart';

import 'channel.dart';

SseChannel connect(Uri url) => HtmlSseChannel.connect(url);
