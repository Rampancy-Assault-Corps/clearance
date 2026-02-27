package art.arcane.racbot.config;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;
import net.dv8tion.jda.api.OnlineStatus;
import org.tomlj.Toml;
import org.tomlj.TomlArray;
import org.tomlj.TomlParseResult;

public class ConfigLoader {
  private static final String DISCORD_TOKEN_ENV = "DISCORD_TOKEN";
  private static final String DISCORD_TOKEN_PROPERTY = "racbot.discordToken";
  private static final String OWNER_IDS_PROPERTY = "racbot.ownerIds";
  private static final String DATA_DIR_PROPERTY = "racbot.dataDir";
  private static final long DEFAULT_HEART_TARGET_USER_ID = 173261518572486656L;
  private static final String DEFAULT_TOML_TEMPLATE =
      """
      # RACBot configuration
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

      [runtime]
      # Discord bot token from Discord Developer Portal.
      # Runtime token precedence:
      #   1) DISCORD_TOKEN environment variable
      #   2) -PdiscordToken=... Gradle run property
      #   3) runtime.discord_token in this TOML
      # Leave blank here if you provide DISCORD_TOKEN or -PdiscordToken.
      discord_token = ""
      # Owner user IDs with command bypass permissions.
      # Example: [123456789012345678, 987654321098765432]
      owner_ids = []
      """;

  public BotConfig load(Path configPath) {
    TomlParseResult result = parse(configPath);

    BotConfig.Bot bot =
        new BotConfig.Bot(
            stringValue(result, "bot.activity", "watching:Support channels"),
            parseOnlineStatus(stringValue(result, "bot.online_status", "ONLINE")),
            CommandRegistrationMode.fromValue(
                stringValue(result, "bot.command_registration_mode", "GLOBAL")),
            nullableLongValue(result, "bot.dev_guild_id"));

    BotConfig.Branding branding =
        new BotConfig.Branding(
            stringValue(result, "branding.company_name", "Arcane Arts"),
            stringValue(result, "branding.primary_color", "#0EA5E9"),
            stringValue(result, "branding.avatar_url", "https://volmit.com/img/logo.png"));

    BotConfig.GuildDefaults guildDefaults =
        new BotConfig.GuildDefaults(
            stringValue(result, "guild_defaults.admin_role_name", "Administrator"),
            stringValue(result, "guild_defaults.support_role_name", "Support"),
            stringValue(result, "guild_defaults.notify_role_suffix", " - Notify"));

    BotConfig.Storage storage =
        new BotConfig.Storage(
            stringValue(result, "storage.data_dir", "./data"),
            booleanValue(result, "storage.atomic_writes", true));

    BotConfig.Logs logs =
        new BotConfig.Logs(
            nullableSnowflakeValue(result, "logs.user_log_channel_id"),
            nullableSnowflakeValue(result, "logs.comm_log_channel_id"),
            nullableSnowflakeValue(result, "logs.audit_log_channel_id"),
            longValue(result, "logs.heart_target_user_id", DEFAULT_HEART_TARGET_USER_ID));

    BotConfig.Features features =
        new BotConfig.Features(
            booleanValue(result, "features.enable_ping", true),
            booleanValue(result, "features.enable_links", false),
            booleanValue(result, "features.enable_logguide", false),
            booleanValue(result, "features.enable_notify", false),
            booleanValue(result, "features.enable_setup", false));

    String token =
        firstNonBlank(
            System.getenv(DISCORD_TOKEN_ENV),
            System.getProperty(DISCORD_TOKEN_PROPERTY),
            stringValue(result, "runtime.discord_token", ""));
    Set<Long> ownerIds =
        parseOwnerIdsWithOverride(
            parseOwnerIds(result, "runtime.owner_ids"), System.getProperty(OWNER_IDS_PROPERTY));
    String dataDir =
        firstNonBlank(
            System.getProperty(DATA_DIR_PROPERTY),
            stringValue(result, "storage.data_dir", "./data"));

    BotConfig.Runtime runtime =
        new BotConfig.Runtime(token, ownerIds, Path.of(dataDir).toAbsolutePath().normalize());

    BotConfig config = new BotConfig(bot, branding, guildDefaults, storage, logs, features, runtime);
    ConfigValidator.validate(config);
    return config;
  }

  private TomlParseResult parse(Path configPath) {
    try {
      Path normalized = configPath.toAbsolutePath().normalize();
      ensureTemplateFiles(normalized);

      TomlParseResult result = Toml.parse(Files.newBufferedReader(normalized));
      if (result.hasErrors()) {
        throw new ConfigException("Invalid TOML config: " + result.errors());
      }
      return result;
    } catch (IOException e) {
      throw new ConfigException("Failed to read config file: " + configPath.toAbsolutePath(), e);
    }
  }

  private static void ensureTemplateFiles(Path configPath) throws IOException {
    Path parent = configPath.getParent();
    if (parent != null) {
      Files.createDirectories(parent);
    }

    if (!Files.exists(configPath)) {
      Files.writeString(
          configPath,
          DEFAULT_TOML_TEMPLATE,
          StandardCharsets.UTF_8,
          StandardOpenOption.CREATE_NEW,
          StandardOpenOption.WRITE);
    }

    Path examplePath = configPath.resolveSibling(configPath.getFileName().toString() + ".example");
    if ("bot.toml".equalsIgnoreCase(configPath.getFileName().toString())) {
      examplePath = configPath.resolveSibling("bot.toml.example");
    }

    if (!Files.exists(examplePath)) {
      Files.writeString(
          examplePath,
          DEFAULT_TOML_TEMPLATE,
          StandardCharsets.UTF_8,
          StandardOpenOption.CREATE_NEW,
          StandardOpenOption.WRITE);
    }
  }

  private static String stringValue(TomlParseResult result, String key, String fallback) {
    String value = result.getString(key);
    return value == null || value.isBlank() ? fallback : value.trim();
  }

  private static long longValue(TomlParseResult result, String key, long fallback) {
    Long value = result.getLong(key);
    return value == null ? fallback : value;
  }

  private static boolean booleanValue(TomlParseResult result, String key, boolean fallback) {
    Boolean value = result.getBoolean(key);
    return value == null ? fallback : value;
  }

  private static Long nullableSnowflakeValue(TomlParseResult result, String key) {
    Long numericValue = result.getLong(key);
    if (numericValue != null) {
      return numericValue <= 0 ? null : numericValue;
    }

    String rawValue = result.getString(key);
    if (rawValue == null || rawValue.isBlank()) {
      return null;
    }

    try {
      long parsed = Long.parseLong(rawValue.trim());
      return parsed <= 0 ? null : parsed;
    } catch (NumberFormatException ex) {
      throw new ConfigException("Invalid snowflake id for " + key + ": " + rawValue, ex);
    }
  }

  private static Long nullableLongValue(TomlParseResult result, String key) {
    return result.getLong(key);
  }

  private static OnlineStatus parseOnlineStatus(String status) {
    try {
      return OnlineStatus.valueOf(status.toUpperCase());
    } catch (IllegalArgumentException ex) {
      return OnlineStatus.ONLINE;
    }
  }

  private static Set<Long> parseOwnerIds(TomlParseResult result, String key) {
    TomlArray values = result.getArray(key);
    if (values == null) {
      return Collections.emptySet();
    }

    Set<Long> ownerIds = new LinkedHashSet<>();
    for (int i = 0; i < values.size(); i++) {
      Object value = values.get(i);
      if (value instanceof Long longValue) {
        ownerIds.add(longValue);
        continue;
      }
      if (value instanceof String stringValue) {
        try {
          ownerIds.add(Long.parseLong(stringValue.trim()));
          continue;
        } catch (NumberFormatException ex) {
          throw new ConfigException("Invalid owner id in runtime.owner_ids: " + stringValue, ex);
        }
      }
      throw new ConfigException("runtime.owner_ids must contain only integers or numeric strings");
    }

    return Set.copyOf(ownerIds);
  }

  private static Set<Long> parseOwnerIdsWithOverride(Set<Long> fallback, String override) {
    if (override == null || override.isBlank()) {
      return fallback;
    }

    Set<Long> ownerIds = new LinkedHashSet<>();
    for (String token : override.split(",")) {
      String trimmed = token.trim();
      if (trimmed.isEmpty()) {
        continue;
      }
      try {
        ownerIds.add(Long.parseLong(trimmed));
      } catch (NumberFormatException ex) {
        throw new ConfigException("Invalid owner id in racbot.ownerIds: " + trimmed, ex);
      }
    }
    return Set.copyOf(ownerIds);
  }

  private static String firstNonBlank(String... values) {
    for (String value : values) {
      if (value != null && !value.isBlank()) {
        return value.trim();
      }
    }
    return "";
  }
}
