import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/config/command_registration_mode.dart';
import 'package:racbot_nyxx/src/model/bot_runtime_components.dart';

typedef RuntimeProvider = BotRuntimeComponents? Function();

class PingCommandModule {
  final CommandsPlugin commandsPlugin;
  final RuntimeProvider runtimeProvider;
  final Logger logger;

  bool _pingCommandAdded = false;

  PingCommandModule({
    required this.commandsPlugin,
    required this.runtimeProvider,
    required this.logger,
  });

  bool get pingCommandAdded => _pingCommandAdded;

  bool ensurePingCommandEnabled({
    required BotConfig config,
    required NyxxGateway client,
  }) {
    if (!config.features.pingEnabled) {
      return false;
    }

    if (_pingCommandAdded) {
      return false;
    }

    Snowflake? preferredGuild = _resolvePreferredGuild(
      config: config,
      client: client,
    );
    commandsPlugin.guild = preferredGuild;
    commandsPlugin.addCommand(_buildPingCommand());
    _pingCommandAdded = true;

    if (preferredGuild != null) {
      logger.info(
        'Added ping command with preferred guild ${preferredGuild.value}',
      );
    } else {
      logger.info('Added ping command with global registration preference');
    }

    return true;
  }

  Snowflake? _resolvePreferredGuild({
    required BotConfig config,
    required NyxxGateway client,
  }) {
    if (config.bot.commandRegistrationMode != CommandRegistrationMode.guild) {
      return null;
    }

    int? guildId = config.bot.devGuildId;
    if (guildId == null) {
      return null;
    }

    Snowflake snowflake = Snowflake(guildId);
    if (!client.guilds.cache.containsKey(snowflake)) {
      return null;
    }

    return snowflake;
  }

  ChatCommand _buildPingCommand() {
    return ChatCommand(
      'ping',
      'Check bot latency',
      id('ping', (ChatContext context) async {
        BotRuntimeComponents? components = runtimeProvider();
        if (components == null) {
          await context.respond(
            MessageBuilder(content: 'Bot runtime is not ready.'),
            level: ResponseLevel.private,
          );
          return;
        }

        if (!components.config.features.pingEnabled) {
          await context.respond(
            MessageBuilder(content: '`/ping` is disabled.'),
            level: ResponseLevel.private,
          );
          return;
        }

        int latencyMs = context.client.gateway.latency.inMilliseconds;
        await context.respond(
          MessageBuilder(content: 'Pong! Gateway ping: `${latencyMs}ms`'),
          level: ResponseLevel.private,
        );
      }),
      options: const CommandOptions(
        type: CommandType.slashOnly,
        defaultResponseLevel: ResponseLevel.private,
      ),
    );
  }
}
