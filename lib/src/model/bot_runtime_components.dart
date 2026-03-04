import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/service/embed_factory.dart';

class BotRuntimeComponents {
  final BotConfig config;
  final EmbedFactory embedFactory;

  const BotRuntimeComponents({
    required this.config,
    required this.embedFactory,
  });
}
