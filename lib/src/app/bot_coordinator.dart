import 'dart:async';
import 'dart:io';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:path/path.dart' as p;
import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/config/config_exception.dart';
import 'package:racbot_nyxx/src/config/config_loader.dart';
import 'package:racbot_nyxx/src/config/config_validator.dart';
import 'package:racbot_nyxx/src/discord/bot_event_handlers.dart';
import 'package:racbot_nyxx/src/discord/command_registrar.dart';
import 'package:racbot_nyxx/src/discord/ping_command_module.dart';
import 'package:racbot_nyxx/src/model/bot_runtime_components.dart';
import 'package:racbot_nyxx/src/service/embed_factory.dart';
import 'package:racbot_nyxx/src/service/firebase_account_link_repository.dart';
import 'package:racbot_nyxx/src/service/runner_role_sync_service.dart';
import 'package:racbot_nyxx/src/util/activity_parser.dart';
import 'package:racbot_nyxx/src/util/app_logger.dart';

class BotCoordinator {
  final AppLogger logger = const AppLogger(scope: 'BotCoordinator');

  final String configPath;
  final ConfigOverrides overrides;
  final ConfigLoader configLoader;
  final CommandRegistrar commandRegistrar;

  bool _running = false;
  bool _tokenMissingNoticeShown = false;
  String? _activeToken;
  String? _lastConfigError;

  BotRuntimeComponents? _runtime;
  NyxxGateway? _client;
  CommandsPlugin? _commandsPlugin;
  PingCommandModule? _pingCommandModule;

  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _watchDebounce;
  Timer? _runnerRoleSyncTimer;

  final List<StreamSubscription<dynamic>> _eventSubscriptions =
      <StreamSubscription<dynamic>>[];

  final Completer<void> _shutdownCompleter = Completer<void>();

  BotCoordinator({
    required this.configPath,
    required this.overrides,
    required this.configLoader,
    required this.commandRegistrar,
  });

  BotRuntimeComponents? runtimeComponents() => _runtime;

  Future<void> start() async {
    _running = true;
    _startWatcher();
    await reload(reason: 'startup');
  }

  Future<void> blockUntilShutdown() => _shutdownCompleter.future;

  Future<void> shutdown() async {
    if (!_running) {
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete();
      }
      return;
    }

    _running = false;
    await _watchSubscription?.cancel();
    _watchSubscription = null;
    _watchDebounce?.cancel();
    _watchDebounce = null;

    await _shutdownClient();

    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }
  }

  Future<void> reload({required String reason}) async {
    if (!_running) {
      return;
    }

    BotConfig config;
    try {
      config = configLoader.load(configPath: configPath, overrides: overrides);
    } on ConfigException catch (error) {
      _handleConfigException(error);
      return;
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to load TOML config from $configPath',
        error,
        stackTrace,
      );
      return;
    }

    _tokenMissingNoticeShown = false;
    _lastConfigError = null;

    try {
      Directory(config.runtime.dataDirPath).createSync(recursive: true);
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Failed to create data directory ${config.runtime.dataDirPath}',
        error,
        stackTrace,
      );
      return;
    }

    BotRuntimeComponents updated = _buildRuntimeComponents(config: config);
    String newToken = updated.config.runtime.discordToken;

    if (_client == null) {
      await _startClient(updated: updated, reason: reason);
      return;
    }

    if (_activeToken != newToken) {
      logger.info('Detected token change in TOML. Reconnecting bot session.');
      await _shutdownClient();
      await _startClient(updated: updated, reason: 'token-change');
      return;
    }

    BotRuntimeComponents? previousRuntime = _runtime;
    _runtime = updated;
    await _applyLiveConfig(updated: updated);
    await _disposeRuntimeComponents(previousRuntime);
    logger.info('Applied TOML hotload ($reason)');
  }

  void _startWatcher() {
    String configDirectoryPath = p.dirname(configPath);
    Directory configDirectory = Directory(configDirectoryPath);

    try {
      configDirectory.createSync(recursive: true);
    } on Object catch (error) {
      _printStartupError(
        title: 'Configuration Directory Missing',
        message: 'Could not resolve configuration directory from $configPath',
        actions: <String>[
          'Ensure --config points to a valid TOML file path.',
          'Then save the file again.',
        ],
      );
      logger.severe(
        'Failed to create config directory $configDirectoryPath',
        error,
      );
      return;
    }

    _watchSubscription = configDirectory.watch().listen((
      FileSystemEvent event,
    ) {
      if (!_running) {
        return;
      }

      String path = event.path.toLowerCase();
      if (!path.endsWith('.toml')) {
        return;
      }

      _watchDebounce?.cancel();
      _watchDebounce = Timer(const Duration(milliseconds: 300), () {
        Future<void> ignored = reload(reason: 'toml-change');
        ignored.catchError((Object _) {});
      });
    });
  }

  BotRuntimeComponents _buildRuntimeComponents({required BotConfig config}) {
    ConfigValidator.validate(config);
    EmbedFactory embedFactory = EmbedFactory(config: config);
    RunnerRoleSyncService? runnerRoleSyncService;
    int? runnerRoleId = config.linkSync.runnerRoleId;
    if (runnerRoleId != null) {
      FirebaseAccountLinkRepository repository = FirebaseAccountLinkRepository(
        serviceAccountPath: config.linkSync.serviceAccountPath,
        logger: const AppLogger(scope: 'FirebaseAccountLinkRepository'),
      );
      runnerRoleSyncService = RunnerRoleSyncService(
        runnerRoleId: runnerRoleId,
        repository: repository,
        logger: const AppLogger(scope: 'RunnerRoleSyncService'),
      );
    }

    return BotRuntimeComponents(
      config: config,
      embedFactory: embedFactory,
      runnerRoleSyncService: runnerRoleSyncService,
    );
  }

  Future<void> _startClient({
    required BotRuntimeComponents updated,
    required String reason,
  }) async {
    _runtime = updated;

    CommandsPlugin commandsPlugin = CommandsPlugin(
      prefix: (MessageCreateEvent _) => '!',
    );
    PingCommandModule pingCommandModule = PingCommandModule(
      commandsPlugin: commandsPlugin,
      runtimeProvider: runtimeComponents,
      logger: const AppLogger(scope: 'PingCommandModule'),
    );

    try {
      NyxxGateway client = await Nyxx.connectGateway(
        updated.config.runtime.discordToken,
        GatewayIntents.guildMembers |
            GatewayIntents.guildMessages |
            GatewayIntents.guildMessageReactions |
            GatewayIntents.guildModeration |
            GatewayIntents.messageContent,
        options: GatewayClientOptions(
          plugins: [commandsPlugin, cliIntegration, ignoreExceptions],
        ),
      );

      _client = client;
      _commandsPlugin = commandsPlugin;
      _pingCommandModule = pingCommandModule;
      _activeToken = updated.config.runtime.discordToken;

      await _registerEventHandlers(client: client);

      bool addedNow = pingCommandModule.ensurePingCommandEnabled(
        config: updated.config,
        client: client,
      );

      if (updated.config.features.pingEnabled && !addedNow) {
        await commandRegistrar.register(
          client: client,
          commandsPlugin: commandsPlugin,
          pingCommandModule: pingCommandModule,
          config: updated.config,
        );
      }

      await _configureRunnerRoleSync(client: client, runtime: updated);
      await _applyPresence(config: updated.config);

      User selfUser = await client.users.fetchCurrentUser();
      String tag = selfUser.discriminator == '0'
          ? selfUser.username
          : '${selfUser.username}#${selfUser.discriminator}';

      logger.info('Bot is online as $tag (trigger: $reason)');
    } on Object catch (error, stackTrace) {
      await _disposeRuntimeComponents(updated);
      _runtime = null;
      _client = null;
      _commandsPlugin = null;
      _pingCommandModule = null;
      _activeToken = null;

      if (_isInvalidTokenError(error)) {
        _printStartupError(
          title: 'Invalid Discord Token',
          message:
              'Discord rejected the configured token. Waiting for a corrected token...',
          actions: <String>[
            'Update [runtime].discord_token in $configPath',
            'Or export env var: DISCORD_TOKEN=YOUR_TOKEN',
            'Or run with: dart run bin/racbot_nyxx.dart --discord-token=YOUR_TOKEN',
            'Save TOML. The bot will auto-retry connection.',
          ],
        );
        return;
      }

      logger.severe('Failed to start Nyxx', error, stackTrace);
      _printStartupError(
        title: 'Discord Startup Error',
        message: '${error.runtimeType}: $error',
        actions: <String>[
          'Fix the issue and save TOML. The bot will retry on change.',
        ],
      );
    }
  }

  Future<void> _applyLiveConfig({required BotRuntimeComponents updated}) async {
    if (_client == null ||
        _commandsPlugin == null ||
        _pingCommandModule == null) {
      return;
    }

    await _configureRunnerRoleSync(client: _client!, runtime: updated);
    await _applyPresence(config: updated.config);

    bool addedNow = _pingCommandModule!.ensurePingCommandEnabled(
      config: updated.config,
      client: _client!,
    );

    if (updated.config.features.pingEnabled && !addedNow) {
      await commandRegistrar.register(
        client: _client!,
        commandsPlugin: _commandsPlugin!,
        pingCommandModule: _pingCommandModule!,
        config: updated.config,
      );
    }
  }

  Future<void> _applyPresence({required BotConfig config}) async {
    if (_client == null) {
      return;
    }

    _client!.updatePresence(
      PresenceBuilder(
        status: ActivityParser.parseStatus(config.bot.onlineStatus),
        isAfk: false,
        activities: <ActivityBuilder>[
          ActivityParser.parse(config.bot.activity),
        ],
      ),
    );
  }

  Future<void> _registerEventHandlers({required NyxxGateway client}) async {
    for (StreamSubscription<dynamic> subscription in _eventSubscriptions) {
      await subscription.cancel();
    }
    _eventSubscriptions.clear();

    BotEventHandlers handlers = BotEventHandlers(
      runtimeProvider: runtimeComponents,
      logger: const AppLogger(scope: 'BotEventHandlers'),
    );

    List<StreamSubscription<dynamic>> subscriptions = handlers.register(
      client: client,
    );
    _eventSubscriptions.addAll(subscriptions);
  }

  Future<void> _shutdownClient() async {
    _runnerRoleSyncTimer?.cancel();
    _runnerRoleSyncTimer = null;

    for (StreamSubscription<dynamic> subscription in _eventSubscriptions) {
      await subscription.cancel();
    }
    _eventSubscriptions.clear();

    NyxxGateway? client = _client;
    if (client != null) {
      logger.info('Shutting down Nyxx...');
      await client.close();
    }

    BotRuntimeComponents? runtime = _runtime;
    _runtime = null;
    _client = null;
    _commandsPlugin = null;
    _pingCommandModule = null;
    _activeToken = null;
    await _disposeRuntimeComponents(runtime);
  }

  Future<void> _configureRunnerRoleSync({
    required NyxxGateway client,
    required BotRuntimeComponents runtime,
  }) async {
    _runnerRoleSyncTimer?.cancel();
    _runnerRoleSyncTimer = null;

    RunnerRoleSyncService? runnerRoleSyncService =
        runtime.runnerRoleSyncService;
    if (runnerRoleSyncService == null) {
      return;
    }

    try {
      await runnerRoleSyncService.syncAllGuilds(client: client, force: true);
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Runner role sync failed during initialization.',
        error,
        stackTrace,
      );
    }

    _runnerRoleSyncTimer = Timer.periodic(RunnerRoleSyncService.syncInterval, (
      Timer _,
    ) {
      Future<void> syncFuture = runnerRoleSyncService.syncAllGuilds(
        client: client,
        force: false,
      );
      syncFuture.catchError((Object error, StackTrace stackTrace) {
        logger.severe(
          'Runner role sync failed during scheduled run.',
          error,
          stackTrace,
        );
      });
    });
  }

  Future<void> _disposeRuntimeComponents(BotRuntimeComponents? runtime) async {
    RunnerRoleSyncService? runnerRoleSyncService =
        runtime?.runnerRoleSyncService;
    if (runnerRoleSyncService == null) {
      return;
    }
    await runnerRoleSyncService.dispose();
  }

  void _handleConfigException(ConfigException exception) {
    String message = exception.message;

    if (message.contains('runtime.discord_token is required')) {
      if (!_tokenMissingNoticeShown) {
        _printStartupError(
          title: 'Waiting For Token',
          message:
              'No Discord token is configured yet. The bot will keep running and watch for TOML updates.',
          actions: <String>[
            'Set [runtime].discord_token in $configPath',
            'Or export env var: DISCORD_TOKEN=YOUR_TOKEN',
            'Or run with override: dart run bin/racbot_nyxx.dart --discord-token=YOUR_TOKEN',
            'Save the TOML file. The bot will auto-connect without restart.',
          ],
        );
        _tokenMissingNoticeShown = true;
      }

      if (_client != null) {
        logger.warning(
          'Config currently has no token. Keeping existing active Discord session until a valid token is provided.',
        );
      }
      return;
    }

    if (message != _lastConfigError) {
      _printStartupError(
        title: 'Configuration Error',
        message: message,
        actions: <String>[
          'Fix the value in $configPath',
          'Save the file. The bot will retry automatically.',
        ],
      );
      _lastConfigError = message;
    }

    if (_client != null) {
      logger.warning(
        'Ignoring invalid TOML update and keeping last known-good runtime.',
      );
    }
  }

  bool _isInvalidTokenError(Object error) {
    if (error is HttpResponseError) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return true;
      }
    }

    String text = error.toString().toLowerCase();
    if (text.contains('invalid token') || text.contains('401 unauthorized')) {
      return true;
    }

    return false;
  }

  void _printStartupError({
    required String title,
    required String message,
    required List<String> actions,
  }) {
    String border = '=' * 98;
    stderr.writeln();
    stderr.writeln(border);
    stderr.writeln('RACBOT STATUS: $title');
    stderr.writeln(border);
    stderr.writeln('Reason:');
    stderr.writeln('  $message');
    if (actions.isNotEmpty) {
      stderr.writeln();
      stderr.writeln('What to do:');
      int index = 1;
      for (String action in actions) {
        stderr.writeln('  $index. $action');
        index += 1;
      }
    }
    stderr.writeln(border);
    stderr.writeln();
  }
}
