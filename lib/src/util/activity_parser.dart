import 'package:nyxx/nyxx.dart';

class ActivityParser {
  const ActivityParser._();

  static ActivityBuilder parse(String? value) {
    String raw = value == null ? '' : value.trim();
    if (raw.isEmpty) {
      return ActivityBuilder(
        name: 'support channels',
        type: ActivityType.watching,
      );
    }

    List<String> split = raw.split(':');
    if (split.length >= 2) {
      String kind = split.first.trim().toLowerCase();
      String text = raw.substring(raw.indexOf(':') + 1).trim();
      return switch (kind) {
        'playing' => ActivityBuilder(name: text, type: ActivityType.game),
        'listening' => ActivityBuilder(
          name: text,
          type: ActivityType.listening,
        ),
        'watching' => ActivityBuilder(name: text, type: ActivityType.watching),
        'competing' => ActivityBuilder(
          name: text,
          type: ActivityType.competing,
        ),
        _ => ActivityBuilder(name: raw, type: ActivityType.watching),
      };
    }

    return ActivityBuilder(name: raw, type: ActivityType.watching);
  }

  static CurrentUserStatus parseStatus(String? value) {
    String normalized = value == null ? '' : value.trim().toUpperCase();
    return switch (normalized) {
      'IDLE' => CurrentUserStatus.idle,
      'DO_NOT_DISTURB' => CurrentUserStatus.dnd,
      'DND' => CurrentUserStatus.dnd,
      'INVISIBLE' => CurrentUserStatus.invisible,
      'OFFLINE' => CurrentUserStatus.offline,
      _ => CurrentUserStatus.online,
    };
  }
}
