import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/service/embed_factory.dart';
import 'package:racbot_nyxx/src/service/role_persistence_service.dart';
import 'package:racbot_nyxx/src/service/runner_role_sync_service.dart';

class BotRuntimeComponents {
  final BotConfig config;
  final EmbedFactory embedFactory;
  final RolePersistenceService rolePersistenceService;
  final RunnerRoleSyncService? runnerRoleSyncService;

  const BotRuntimeComponents({
    required this.config,
    required this.embedFactory,
    required this.rolePersistenceService,
    required this.runnerRoleSyncService,
  });
}
