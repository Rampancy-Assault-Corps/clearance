import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fast_log/fast_log.dart';
import 'package:path/path.dart' as p;
import 'package:racbot_nyxx/src/app/bot_coordinator.dart';
import 'package:racbot_nyxx/src/config/config_loader.dart';
import 'package:racbot_nyxx/src/discord/command_registrar.dart';
import 'package:racbot_nyxx/src/util/app_logger.dart';

Future<void> main(List<String> args) async {
  ArgParser parser = ArgParser()
    ..addOption('config', defaultsTo: 'config/bot.toml')
    ..addOption('discord-token')
    ..addOption('owner-ids')
    ..addOption('data-dir')
    ..addFlag('help', abbr: 'h', negatable: false);

  ArgResults results = parser.parse(args);

  if (results['help'] == true) {
    info(parser.usage);
    return;
  }

  String configPath = p.normalize(p.absolute(results['config'] as String));
  String? discordToken = results['discord-token'] as String?;
  String? ownerIds = results['owner-ids'] as String?;
  String? dataDir = results['data-dir'] as String?;

  ConfigOverrides overrides = ConfigOverrides(
    discordToken: discordToken,
    ownerIds: ownerIds,
    dataDir: dataDir,
  );

  BotCoordinator coordinator = BotCoordinator(
    configPath: configPath,
    overrides: overrides,
    configLoader: ConfigLoader(),
    commandRegistrar: CommandRegistrar(
      logger: const AppLogger(scope: 'CommandRegistrar'),
    ),
  );

  StreamSubscription<ProcessSignal> sigIntSubscription = ProcessSignal.sigint
      .watch()
      .listen((ProcessSignal _) {
        Future<void> ignored = coordinator.shutdown();
        ignored.catchError((Object _) {});
      });

  StreamSubscription<ProcessSignal> sigTermSubscription = ProcessSignal.sigterm
      .watch()
      .listen((ProcessSignal _) {
        Future<void> ignored = coordinator.shutdown();
        ignored.catchError((Object _) {});
      });

  try {
    await coordinator.start();
    await coordinator.blockUntilShutdown();
  } finally {
    await sigIntSubscription.cancel();
    await sigTermSubscription.cancel();
  }
}
