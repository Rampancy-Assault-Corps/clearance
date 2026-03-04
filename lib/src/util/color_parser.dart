import 'package:nyxx/nyxx.dart';

class ColorParser {
  const ColorParser._();

  static DiscordColor parseHex(String? color) {
    String normalized = color == null ? '' : color.trim();
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    return DiscordColor(int.parse(normalized, radix: 16));
  }
}
