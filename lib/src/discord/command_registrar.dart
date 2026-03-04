import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/config/command_registration_mode.dart';
import 'package:racbot_nyxx/src/discord/ping_command_module.dart';
import 'package:racbot_nyxx/src/util/app_logger.dart';

class CommandRegistrar {
  final AppLogger logger;

  const CommandRegistrar({required this.logger});

  Future<void> register({
    required NyxxGateway client,
    required CommandsPlugin commandsPlugin,
    required PingCommandModule pingCommandModule,
    required BotConfig config,
  }) async {
    if (!config.features.pingEnabled) {
      logger.warning(
        'No commands enabled. Skipping slash command registration.',
      );
      return;
    }

    if (!pingCommandModule.pingCommandAdded) {
      logger.warning(
        'Ping command is enabled in config but not attached to nyxx_commands yet.',
      );
      return;
    }

    List<ApplicationCommandBuilder> builders = <ApplicationCommandBuilder>[
      ApplicationCommandBuilder.chatInput(
        name: 'ping',
        description: 'Check bot latency',
        options: <CommandOptionBuilder>[],
      ),
    ];

    if (config.bot.commandRegistrationMode == CommandRegistrationMode.guild &&
        config.bot.devGuildId != null) {
      Snowflake guildId = Snowflake(config.bot.devGuildId!);
      if (client.guilds.cache.containsKey(guildId)) {
        List<ApplicationCommand> registered = await client
            .guilds[guildId]
            .commands
            .bulkOverride(builders);

        commandsPlugin.registeredCommands.clear();
        commandsPlugin.registeredCommands.addAll(registered);

        logger.info(
          'Registered ${registered.length} commands in dev guild ${guildId.value}',
        );
        return;
      }

      logger.warning(
        'Configured dev guild ${config.bot.devGuildId} not found, falling back to global command registration.',
      );
    }

    List<ApplicationCommand> registered = await client.commands.bulkOverride(
      builders,
    );
    commandsPlugin.registeredCommands.clear();
    commandsPlugin.registeredCommands.addAll(registered);
    logger.info('Registered ${registered.length} commands globally.');
  }
}
