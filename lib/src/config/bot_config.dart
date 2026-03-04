import 'package:racbot_nyxx/src/config/command_registration_mode.dart';

class BotConfig {
  final BotSection bot;
  final BrandingSection branding;
  final GuildDefaultsSection guildDefaults;
  final StorageSection storage;
  final LogsSection logs;
  final FeaturesSection features;
  final RuntimeSection runtime;

  const BotConfig({
    required this.bot,
    required this.branding,
    required this.guildDefaults,
    required this.storage,
    required this.logs,
    required this.features,
    required this.runtime,
  });
}

class BotSection {
  final String activity;
  final String onlineStatus;
  final CommandRegistrationMode commandRegistrationMode;
  final int? devGuildId;

  const BotSection({
    required this.activity,
    required this.onlineStatus,
    required this.commandRegistrationMode,
    required this.devGuildId,
  });
}

class BrandingSection {
  final String companyName;
  final String primaryColorHex;
  final String avatarUrl;

  const BrandingSection({
    required this.companyName,
    required this.primaryColorHex,
    required this.avatarUrl,
  });
}

class GuildDefaultsSection {
  final String adminRoleName;
  final String supportRoleName;
  final String notifyRoleSuffix;

  const GuildDefaultsSection({
    required this.adminRoleName,
    required this.supportRoleName,
    required this.notifyRoleSuffix,
  });
}

class StorageSection {
  final String dataDir;
  final bool atomicWrites;

  const StorageSection({required this.dataDir, required this.atomicWrites});
}

class LogsSection {
  final int? userLogChannelId;
  final int? commLogChannelId;
  final int? auditLogChannelId;
  final int heartTargetUserId;

  const LogsSection({
    required this.userLogChannelId,
    required this.commLogChannelId,
    required this.auditLogChannelId,
    required this.heartTargetUserId,
  });
}

class FeaturesSection {
  final bool pingEnabled;
  final bool linksEnabled;
  final bool logGuideEnabled;
  final bool notifyEnabled;
  final bool setupEnabled;

  const FeaturesSection({
    required this.pingEnabled,
    required this.linksEnabled,
    required this.logGuideEnabled,
    required this.notifyEnabled,
    required this.setupEnabled,
  });
}

class RuntimeSection {
  final String discordToken;
  final Set<int> ownerIds;
  final String dataDirPath;

  const RuntimeSection({
    required this.discordToken,
    required this.ownerIds,
    required this.dataDirPath,
  });
}
