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
    _validateOptionalSnowflake(
      value: config.logs.auditLogChannelId,
      key: 'logs.audit_log_channel_id',
    );

    if (config.logs.heartTargetUserId <= 0) {
      throw const ConfigException(
        message:
            'logs.heart_target_user_id must be a positive Discord user id.',
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
}
