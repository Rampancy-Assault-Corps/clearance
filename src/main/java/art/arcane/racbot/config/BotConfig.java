package art.arcane.racbot.config;

import java.nio.file.Path;
import java.util.Set;
import net.dv8tion.jda.api.OnlineStatus;

public record BotConfig(
    Bot bot,
    Branding branding,
    GuildDefaults guildDefaults,
    Storage storage,
    Logs logs,
    Features features,
    Runtime runtime) {

  public record Bot(
      String activity,
      OnlineStatus onlineStatus,
      CommandRegistrationMode commandRegistrationMode,
      Long devGuildId) {}

  public record Branding(String companyName, String primaryColorHex, String avatarUrl) {}

  public record GuildDefaults(
      String adminRoleName,
      String supportRoleName,
      String notifyRoleSuffix) {}

  public record Storage(String dataDir, boolean atomicWrites) {}

  public record Logs(
      Long userLogChannelId,
      Long commLogChannelId,
      Long auditLogChannelId,
      Long heartTargetUserId) {}

  public record Features(
      boolean pingEnabled,
      boolean linksEnabled,
      boolean logGuideEnabled,
      boolean notifyEnabled,
      boolean setupEnabled) {}

  public record Runtime(String discordToken, Set<Long> ownerIds, Path dataDirPath) {}
}
