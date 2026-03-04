import 'package:racbot_nyxx/src/util/discord_formatters.dart';
import 'package:racbot_nyxx/src/util/reaction_utils.dart';
import 'package:racbot_nyxx/src/util/text_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ReactionUtils', () {
    test('recognizes supported heart emoji', () {
      expect(ReactionUtils.isSupportedHeartEmoji('❤'), isTrue);
      expect(ReactionUtils.isSupportedHeartEmoji('❤️'), isTrue);
      expect(ReactionUtils.isSupportedHeartEmoji('♥'), isTrue);
      expect(ReactionUtils.isSupportedHeartEmoji('😀'), isFalse);
    });
  });

  group('TextUtils', () {
    test('truncates content with ellipsis', () {
      String value = TextUtils.truncate(value: 'abcdefghij', maxLength: 8);
      expect(value, 'abcde...');
    });

    test('returns empty string when value is blank', () {
      String value = TextUtils.truncate(value: '   ', maxLength: 8);
      expect(value, '');
    });
  });

  group('DiscordFormatters', () {
    test('formats jump url and mentions', () {
      String jump = DiscordFormatters.messageJumpUrl(
        guildId: 1,
        channelId: 2,
        messageId: 3,
      );

      expect(jump, 'https://discord.com/channels/1/2/3');
      expect(DiscordFormatters.userMention(userId: 55), '<@55>');
      expect(DiscordFormatters.channelMention(channelId: 66), '<#66>');
    });
  });
}
