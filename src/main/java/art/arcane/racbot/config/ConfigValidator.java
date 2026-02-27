package art.arcane.racbot.config;

import java.nio.file.Path;
import java.util.regex.Pattern;

public final class ConfigValidator {
  private static final Pattern HEX_COLOR = Pattern.compile("^#?[0-9a-fA-F]{6}$");

  private ConfigValidator() {}

  public static void validate(BotConfig config) {
    requireNonBlank(
        config.runtime().discordToken(),
        "runtime.discord_token is required unless DISCORD_TOKEN is set. "
            + "You can also pass -PdiscordToken=... for Gradle run tasks.");

    if (!HEX_COLOR.matcher(config.branding().primaryColorHex()).matches()) {
      throw new ConfigException(
          "branding.primary_color must be a 6 digit hex color (example: #0EA5E9)");
    }

    validateOptionalSnowflake(config.logs().userLogChannelId(), "logs.user_log_channel_id");
    validateOptionalSnowflake(config.logs().commLogChannelId(), "logs.comm_log_channel_id");
    validateOptionalSnowflake(config.logs().auditLogChannelId(), "logs.audit_log_channel_id");

    if (config.logs().heartTargetUserId() == null || config.logs().heartTargetUserId() <= 0) {
      throw new ConfigException("logs.heart_target_user_id must be a positive Discord user id.");
    }

    Path dataPath = config.runtime().dataDirPath();
    if (dataPath == null) {
      throw new ConfigException("storage.data_dir must resolve to a valid path.");
    }
  }

  private static void requireNonBlank(String value, String message) {
    if (value == null || value.isBlank()) {
      throw new ConfigException(message);
    }
  }

  private static void validateOptionalSnowflake(Long value, String key) {
    if (value != null && value <= 0) {
      throw new ConfigException(key + " must be a positive Discord channel id.");
    }
  }
}
