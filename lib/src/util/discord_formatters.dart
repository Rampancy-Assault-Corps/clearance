class DiscordFormatters {
  const DiscordFormatters._();

  static String userMention({required int userId}) =>
      userId <= 0 ? '`unknown`' : '<@$userId>';

  static String channelMention({required int channelId}) => '<#$channelId>';

  static String messageJumpUrl({
    required int guildId,
    required int channelId,
    required int messageId,
  }) {
    return 'https://discord.com/channels/$guildId/$channelId/$messageId';
  }
}
