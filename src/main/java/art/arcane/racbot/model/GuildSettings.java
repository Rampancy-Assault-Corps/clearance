package art.arcane.racbot.model;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

public class GuildSettings {
  private long guildId;
  private Set<Long> adminRoleIds = new LinkedHashSet<>();
  private Set<Long> supportRoleIds = new LinkedHashSet<>();
  private Map<String, Long> notifyRoleIdsByTopic = new LinkedHashMap<>();
  private Instant createdAt;
  private Instant updatedAt;

  public GuildSettings() {
    // Jackson constructor.
  }

  public static GuildSettings create(long guildId) {
    GuildSettings settings = new GuildSettings();
    settings.guildId = guildId;
    Instant now = Instant.now();
    settings.createdAt = now;
    settings.updatedAt = now;
    return settings;
  }

  public void touch() {
    if (createdAt == null) {
      createdAt = Instant.now();
    }
    updatedAt = Instant.now();
  }

  public long getGuildId() {
    return guildId;
  }

  public void setGuildId(long guildId) {
    this.guildId = guildId;
  }

  public Set<Long> getAdminRoleIds() {
    return adminRoleIds;
  }

  public void setAdminRoleIds(Set<Long> adminRoleIds) {
    this.adminRoleIds = adminRoleIds == null ? new LinkedHashSet<>() : adminRoleIds;
  }

  public Set<Long> getSupportRoleIds() {
    return supportRoleIds;
  }

  public void setSupportRoleIds(Set<Long> supportRoleIds) {
    this.supportRoleIds = supportRoleIds == null ? new LinkedHashSet<>() : supportRoleIds;
  }

  public Map<String, Long> getNotifyRoleIdsByTopic() {
    return notifyRoleIdsByTopic;
  }

  public void setNotifyRoleIdsByTopic(Map<String, Long> notifyRoleIdsByTopic) {
    this.notifyRoleIdsByTopic =
        notifyRoleIdsByTopic == null ? new LinkedHashMap<>() : notifyRoleIdsByTopic;
  }

  public Instant getCreatedAt() {
    return createdAt;
  }

  public void setCreatedAt(Instant createdAt) {
    this.createdAt = createdAt;
  }

  public Instant getUpdatedAt() {
    return updatedAt;
  }

  public void setUpdatedAt(Instant updatedAt) {
    this.updatedAt = updatedAt;
  }
}
