import 'package:sse_channel/io.dart';

import 'channel.dart';

SseChannel connect(Uri url) => IOSseChannel.connect(url);
