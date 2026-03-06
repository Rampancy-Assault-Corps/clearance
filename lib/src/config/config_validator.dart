import 'package:racbot_nyxx/src/config/bot_config.dart';
import 'package:racbot_nyxx/src/config/config_exception.dart';

class ConfigValidator {
  static final RegExp _hexColor = RegExp(r'^#?[0-9a-fA-F]{6}$');

  const ConfigValidator._();

  static void validate(BotConfig config) {
    if (config.runtime.discordToken.trim().isEmpty) {
      throw const ConfigException(
        message:
            'runtime.discord_token is required unless DISCORD_TOKEN is set. You can also pass --discord-token=... .',
      );
    }

    if (!_hexColor.hasMatch(config.branding.primaryColorHex)) {
      throw const ConfigException(
        message:
            'branding.primary_color must be a 6 digit hex color (example: #0EA5E9)',
      );
    }

    _validateOptionalSnowflake(
      value: config.logs.userLogChannelId,
      key: 'logs.user_log_channel_id',
    );
    _validateOptionalSnowflake(
      value: config.logs.commLogChannelId,
      key: 'logs.comm_log_channel_id',
    );
    _validateSnowflakeSet(
      values: config.logs.commLogCategoryIds,
      key: 'logs.comm_log_category_ids',
    );
    _validateSnowflakeSet(
      values: config.logs.commLogSourceChannelIds,
      key: 'logs.comm_log_source_channel_ids',
    );
    _validateOptionalSnowflake(
      value: config.logs.auditLogChannelId,
      key: 'logs.audit_log_channel_id',
    );
    _validateOptionalSnowflake(
      value: config.linkSync.runnerRoleId,
      key: 'link_sync.runner_role_id',
    );

    if (config.logs.heartTargetUserId <= 0) {
      throw const ConfigException(
        message:
            'logs.heart_target_user_id must be a positive Discord user id.',
      );
    }

    bool deleteLogConfigured =
        config.logs.commLogCategoryIds.isNotEmpty ||
        config.logs.commLogSourceChannelIds.isNotEmpty;
    if (deleteLogConfigured && config.logs.commLogChannelId == null) {
      throw const ConfigException(
        message:
            'logs.comm_log_channel_id must be set when delete log category or channel filters are configured.',
      );
    }

    if (config.linkSync.runnerRoleId != null &&
        config.linkSync.serviceAccountPath.trim().isEmpty) {
      throw const ConfigException(
        message: 'link_sync.service_account_path must resolve to a valid path.',
      );
    }

    if (config.runtime.dataDirPath.trim().isEmpty) {
      throw const ConfigException(
        message: 'storage.data_dir must resolve to a valid path.',
      );
    }
  }

  static void _validateOptionalSnowflake({
    required int? value,
    required String key,
  }) {
    if (value != null && value <= 0) {
      throw ConfigException(
        message: '$key must be a positive Discord channel id.',
      );
    }
  }

  static void _validateSnowflakeSet({
    required Set<int> values,
    required String key,
  }) {
    for (int value in values) {
      if (value <= 0) {
        throw ConfigException(message: '$key must contain only positive ids.');
      }
    }
  }
}
