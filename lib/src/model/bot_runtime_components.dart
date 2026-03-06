import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/service/embed_factory.dart';
import 'package:racbot_nyxx/src/service/runner_role_sync_service.dart';

class BotRuntimeComponents {
  final BotConfig config;
  final EmbedFactory embedFactory;
  final RunnerRoleSyncService? runnerRoleSyncService;

  const BotRuntimeComponents({
    required this.config,
    required this.embedFactory,
    required this.runnerRoleSyncService,
  });
}
