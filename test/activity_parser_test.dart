import 'package:nyxx/nyxx.dart';
import 'package:racbot_nyxx/src/util/activity_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ActivityParser', () {
    test('parses playing activity', () {
      ActivityBuilder activity = ActivityParser.parse('playing:Destiny 2');
      expect(activity.name, 'Destiny 2');
      expect(activity.type, ActivityType.game);
    });

    test('falls back to watching for unknown type', () {
      ActivityBuilder activity = ActivityParser.parse('unknown:Something');
      expect(activity.name, 'unknown:Something');
      expect(activity.type, ActivityType.watching);
    });

    test('parses status values', () {
      expect(ActivityParser.parseStatus('ONLINE'), CurrentUserStatus.online);
      expect(ActivityParser.parseStatus('IDLE'), CurrentUserStatus.idle);
      expect(
        ActivityParser.parseStatus('DO_NOT_DISTURB'),
        CurrentUserStatus.dnd,
      );
      expect(
        ActivityParser.parseStatus('INVISIBLE'),
        CurrentUserStatus.invisible,
      );
      expect(ActivityParser.parseStatus('INVALID'), CurrentUserStatus.online);
    });
  });
}
