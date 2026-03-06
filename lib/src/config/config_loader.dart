import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/config/command_registration_mode.dart';
import 'package:racbot_nyxx/src/config/config_exception.dart';
import 'package:racbot_nyxx/src/config/config_validator.dart';
import 'package:toml/toml.dart';

class ConfigOverrides {
  final String? discordToken;
  final String? ownerIds;
  final String? dataDir;

  const ConfigOverrides({
    required this.discordToken,
    required this.ownerIds,
    required this.dataDir,
  });
}

class ConfigLoader {
  final Map<String, String> environment;

  ConfigLoader({Map<String, String>? environment})
    : environment = environment ?? Platform.environment;

  static const String _defaultTemplate = '''# RACBot configuration
# This file is hot-reloaded while the bot is running.
# Save changes to apply them without restart (except Discord session token swaps may reconnect).

[bot]
# Activity format:
#   watching:<text>
#   playing:<text>
#   listening:<text>
#   competing:<text>
activity = "watching:Support channels"
# Allowed values: ONLINE, IDLE, DO_NOT_DISTURB, INVISIBLE
online_status = "ONLINE"
# Command registration strategy:
#   GLOBAL -> register commands globally (can take time to propagate)
#   GUILD  -> register commands only in dev_guild_id (fast for development)
command_registration_mode = "GLOBAL"
# Required only when command_registration_mode = "GUILD".
# Use your Discord server ID.
# dev_guild_id = 123456789012345678

[branding]
# Company/brand label shown in embeds and footer text.
company_name = "Arcane Arts"
# Primary embed color in hex (6 digits, with or without leading #).
primary_color = "#0EA5E9"
# Icon URL used in embed footers.
avatar_url = "https://volmit.com/img/logo.png"

[storage]
# Base folder for bot runtime data.
# Relative paths are resolved from the process working directory.
data_dir = "./data"
# true  -> write JSON via temp+move strategy (safer)
# false -> direct writes
atomic_writes = true

[logs]
# Channel IDs for log output.
# Leave as 0 to disable a given log stream.
user_log_channel_id = 0
comm_log_channel_id = 0
comm_log_category_ids = []
comm_log_source_channel_ids = []
audit_log_channel_id = 0
# When someone reacts with a heart to this user's message,
# the bot will add a heart reaction too.
heart_target_user_id = 173261518572486656

[features]
# Feature flags (true/false) for command modules.
enable_ping = true
enable_links = false
enable_logguide = false
enable_notify = false
enable_setup = false

[link_sync]
runner_role_id = 0
service_account_path = "./service-account.json"

[runtime]
# Discord bot token from Discord Developer Portal.
# Runtime token precedence:
#   1) DISCORD_TOKEN environment variable
#   2) --discord-token=... CLI flag
#   3) runtime.discord_token in this TOML
# Leave blank here if you provide DISCORD_TOKEN or --discord-token.
discord_token = ""
# Owner user IDs with command bypass permissions.
# Example: [123456789012345678, 987654321098765432]
owner_ids = []
''';

  BotConfig load({
    required String configPath,
    required ConfigOverrides overrides,
  }) {
    String normalizedPath = p.normalize(p.absolute(configPath));
    _ensureTemplateFiles(configPath: normalizedPath);

    String content;
    try {
      content = File(normalizedPath).readAsStringSync();
    } on Object catch (error) {
      throw ConfigException(
        message: 'Failed to read config file: $normalizedPath',
        cause: error,
      );
    }

    Map<Object?, Object?> rootMap;
    try {
      rootMap = TomlDocument.parse(content).toMap();
    } on Object catch (error) {
      throw ConfigException(
        message: 'Invalid TOML config: $error',
        cause: error,
      );
    }

    Map<String, Object?> botSection = _section(rootMap: rootMap, key: 'bot');
    Map<String, Object?> brandingSection = _section(
      rootMap: rootMap,
      key: 'branding',
    );
    Map<String, Object?> guildDefaultsSection = _section(
      rootMap: rootMap,
      key: 'guild_defaults',
    );
    Map<String, Object?> storageSection = _section(
      rootMap: rootMap,
      key: 'storage',
    );
    Map<String, Object?> logsSection = _section(rootMap: rootMap, key: 'logs');
    Map<String, Object?> featuresSection = _section(
      rootMap: rootMap,
      key: 'features',
    );
    Map<String, Object?> linkSyncSection = _section(
      rootMap: rootMap,
      key: 'link_sync',
    );
    Map<String, Object?> runtimeSection = _section(
      rootMap: rootMap,
      key: 'runtime',
    );
    String configDirectoryPath = p.dirname(normalizedPath);

    BotSection bot = BotSection(
      activity: _stringValue(
        section: botSection,
        key: 'activity',
        fallback: 'watching:Support channels',
      ),
      onlineStatus: _stringValue(
        section: botSection,
        key: 'online_status',
        fallback: 'ONLINE',
      ),
      commandRegistrationMode: CommandRegistrationMode.fromValue(
        _stringValue(
          section: botSection,
          key: 'command_registration_mode',
          fallback: 'GLOBAL',
        ),
      ),
      devGuildId: _nullableIntValue(section: botSection, key: 'dev_guild_id'),
    );

    BrandingSection branding = BrandingSection(
      companyName: _stringValue(
        section: brandingSection,
        key: 'company_name',
        fallback: 'Arcane Arts',
      ),
      primaryColorHex: _stringValue(
        section: brandingSection,
        key: 'primary_color',
        fallback: '#0EA5E9',
      ),
      avatarUrl: _stringValue(
        section: brandingSection,
        key: 'avatar_url',
        fallback: 'https://volmit.com/img/logo.png',
      ),
    );

    GuildDefaultsSection guildDefaults = GuildDefaultsSection(
      adminRoleName: _stringValue(
        section: guildDefaultsSection,
        key: 'admin_role_name',
        fallback: 'Administrator',
      ),
      supportRoleName: _stringValue(
        section: guildDefaultsSection,
        key: 'support_role_name',
        fallback: 'Support',
      ),
      notifyRoleSuffix: _stringValue(
        section: guildDefaultsSection,
        key: 'notify_role_suffix',
        fallback: ' - Notify',
      ),
    );

    StorageSection storage = StorageSection(
      dataDir: _stringValue(
        section: storageSection,
        key: 'data_dir',
        fallback: './data',
      ),
      atomicWrites: _boolValue(
        section: storageSection,
        key: 'atomic_writes',
        fallback: true,
      ),
    );

    LogsSection logs = LogsSection(
      userLogChannelId: _nullableSnowflakeValue(
        section: logsSection,
        key: 'user_log_channel_id',
      ),
      commLogChannelId: _nullableSnowflakeValue(
        section: logsSection,
        key: 'comm_log_channel_id',
      ),
      commLogCategoryIds: _snowflakeSetValue(
        section: logsSection,
        key: 'comm_log_category_ids',
      ),
      commLogSourceChannelIds: _snowflakeSetValue(
        section: logsSection,
        key: 'comm_log_source_channel_ids',
      ),
      auditLogChannelId: _nullableSnowflakeValue(
        section: logsSection,
        key: 'audit_log_channel_id',
      ),
      heartTargetUserId: _intValue(
        section: logsSection,
        key: 'heart_target_user_id',
        fallback: 173261518572486656,
      ),
    );

    FeaturesSection features = FeaturesSection(
      pingEnabled: _boolValue(
        section: featuresSection,
        key: 'enable_ping',
        fallback: true,
      ),
      linksEnabled: _boolValue(
        section: featuresSection,
        key: 'enable_links',
        fallback: false,
      ),
      logGuideEnabled: _boolValue(
        section: featuresSection,
        key: 'enable_logguide',
        fallback: false,
      ),
      notifyEnabled: _boolValue(
        section: featuresSection,
        key: 'enable_notify',
        fallback: false,
      ),
      setupEnabled: _boolValue(
        section: featuresSection,
        key: 'enable_setup',
        fallback: false,
      ),
    );

    LinkSyncSection linkSync = LinkSyncSection(
      runnerRoleId: _nullableSnowflakeValue(
        section: linkSyncSection,
        key: 'runner_role_id',
      ),
      serviceAccountPath: _resolvePath(
        baseDirectoryPath: configDirectoryPath,
        value: _stringValue(
          section: linkSyncSection,
          key: 'service_account_path',
          fallback: './service-account.json',
        ),
      ),
    );

    String envToken = environment['DISCORD_TOKEN'] ?? '';
    String token = _firstNonBlank(
      values: <String?>[
        envToken,
        overrides.discordToken,
        _stringValue(
          section: runtimeSection,
          key: 'discord_token',
          fallback: '',
        ),
      ],
    );

    Set<int> ownerIds = _parseOwnerIds(
      section: runtimeSection,
      key: 'owner_ids',
    );
    Set<int> ownerIdsWithOverride = _parseOwnerIdsWithOverride(
      fallback: ownerIds,
      override: overrides.ownerIds,
    );

    String dataDir = _firstNonBlank(
      values: <String?>[overrides.dataDir, storage.dataDir],
    );
    String dataDirPath = p.normalize(p.absolute(dataDir));

    RuntimeSection runtime = RuntimeSection(
      discordToken: token,
      ownerIds: ownerIdsWithOverride,
      dataDirPath: dataDirPath,
    );

    BotConfig config = BotConfig(
      bot: bot,
      branding: branding,
      guildDefaults: guildDefaults,
      storage: storage,
      logs: logs,
      features: features,
      linkSync: linkSync,
      runtime: runtime,
    );

    ConfigValidator.validate(config);
    return config;
  }

  static Map<String, Object?> _section({
    required Map<Object?, Object?> rootMap,
    required String key,
  }) {
    Object? value = rootMap[key];
    if (value is Map) {
      Map<dynamic, dynamic> dynamicMap = value;
      Map<String, Object?> result = <String, Object?>{};
      for (MapEntry<dynamic, dynamic> entry in dynamicMap.entries) {
        Object? rawKey = entry.key;
        if (rawKey is String) {
          result[rawKey] = entry.value;
        }
      }
      return result;
    }
    return <String, Object?>{};
  }

  static String _stringValue({
    required Map<String, Object?> section,
    required String key,
    required String fallback,
  }) {
    Object? raw = section[key];
    if (raw == null) {
      return fallback;
    }
    String value = raw.toString().trim();
    return value.isEmpty ? fallback : value;
  }

  static int _intValue({
    required Map<String, Object?> section,
    required String key,
    required int fallback,
  }) {
    Object? raw = section[key];
    if (raw == null) {
      return fallback;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    int? parsed = int.tryParse(raw.toString().trim());
    return parsed ?? fallback;
  }

  static bool _boolValue({
    required Map<String, Object?> section,
    required String key,
    required bool fallback,
  }) {
    Object? raw = section[key];
    if (raw == null) {
      return fallback;
    }
    if (raw is bool) {
      return raw;
    }
    String normalized = raw.toString().trim().toLowerCase();
    return switch (normalized) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };
  }

  static int? _nullableIntValue({
    required Map<String, Object?> section,
    required String key,
  }) {
    Object? raw = section[key];
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    String text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    int? parsed = int.tryParse(text);
    return parsed;
  }

  static int? _nullableSnowflakeValue({
    required Map<String, Object?> section,
    required String key,
  }) {
    Object? raw = section[key];
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw <= 0 ? null : raw;
    }
    if (raw is num) {
      int value = raw.toInt();
      return value <= 0 ? null : value;
    }
    String text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    int? parsed = int.tryParse(text);
    if (parsed == null) {
      throw ConfigException(message: 'Invalid snowflake id for $key: $text');
    }
    return parsed <= 0 ? null : parsed;
  }

  static Set<int> _parseOwnerIds({
    required Map<String, Object?> section,
    required String key,
  }) {
    Object? raw = section[key];
    if (raw == null) {
      return <int>{};
    }
    if (raw is! List) {
      throw const ConfigException(
        message:
            'runtime.owner_ids must contain only integers or numeric strings',
      );
    }

    List<dynamic> values = raw;
    Set<int> ids = <int>{};
    for (Object? value in values) {
      if (value is int) {
        ids.add(value);
      } else if (value is num) {
        ids.add(value.toInt());
      } else if (value is String) {
        int? parsed = int.tryParse(value.trim());
        if (parsed == null) {
          throw ConfigException(
            message: 'Invalid owner id in runtime.owner_ids: $value',
          );
        }
        ids.add(parsed);
      } else {
        throw const ConfigException(
          message:
              'runtime.owner_ids must contain only integers or numeric strings',
        );
      }
    }
    return ids;
  }

  static Set<int> _parseOwnerIdsWithOverride({
    required Set<int> fallback,
    required String? override,
  }) {
    if (override == null || override.trim().isEmpty) {
      return fallback;
    }

    Set<int> ids = <int>{};
    List<String> parts = override.split(',');
    for (String part in parts) {
      String trimmed = part.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      int? parsed = int.tryParse(trimmed);
      if (parsed == null) {
        throw ConfigException(
          message: 'Invalid owner id in --owner-ids: $trimmed',
        );
      }
      ids.add(parsed);
    }

    return ids;
  }

  static Set<int> _snowflakeSetValue({
    required Map<String, Object?> section,
    required String key,
  }) {
    Object? raw = section[key];
    if (raw == null) {
      return <int>{};
    }
    if (raw is! List) {
      throw ConfigException(message: '$key must be a list of Discord ids.');
    }

    Set<int> values = <int>{};
    for (Object? item in raw) {
      int? value = _snowflakeListItemValue(value: item);
      if (value == null) {
        throw ConfigException(message: 'Invalid Discord id in $key: $item');
      }
      values.add(value);
    }
    return values;
  }

  static int? _snowflakeListItemValue({required Object? value}) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is num) {
      int parsed = value.toInt();
      return parsed > 0 ? parsed : null;
    }
    if (value is String) {
      int? parsed = int.tryParse(value.trim());
      if (parsed == null || parsed <= 0) {
        return null;
      }
      return parsed;
    }
    return null;
  }

  static String _firstNonBlank({required List<String?> values}) {
    for (String? value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  static String _resolvePath({
    required String baseDirectoryPath,
    required String value,
  }) {
    String normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      return '';
    }
    if (p.isAbsolute(normalizedValue)) {
      return p.normalize(normalizedValue);
    }
    return p.normalize(p.absolute(p.join(baseDirectoryPath, normalizedValue)));
  }

  static void _ensureTemplateFiles({required String configPath}) {
    File configFile = File(configPath);
    Directory configDirectory = configFile.parent;
    if (!configDirectory.existsSync()) {
      configDirectory.createSync(recursive: true);
    }

    if (!configFile.existsSync()) {
      configFile.writeAsStringSync(_defaultTemplate);
    }

    String fileName = p.basename(configPath);
    String exampleName = fileName.toLowerCase() == 'bot.toml'
        ? 'bot.toml.example'
        : '$fileName.example';
    String examplePath = p.join(configDirectory.path, exampleName);
    File exampleFile = File(examplePath);

    if (!exampleFile.existsSync()) {
      exampleFile.writeAsStringSync(_defaultTemplate);
    }
  }
}
