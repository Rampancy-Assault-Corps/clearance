class ReactionUtils {
  static const Set<String> heartReactionNames = <String>{'❤', '❤️', '♥'};
  static const String heartEmoji = '❤️';

  const ReactionUtils._();

  static bool isSupportedHeartEmoji(String reactionName) =>
      heartReactionNames.contains(reactionName);
}
