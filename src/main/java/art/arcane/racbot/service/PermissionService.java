package art.arcane.racbot.service;

import art.arcane.racbot.config.BotConfig;
import art.arcane.racbot.model.GuildSettings;
import java.util.Set;
import net.dv8tion.jda.api.Permission;
import net.dv8tion.jda.api.entities.Member;

public class PermissionService {
  private final Set<Long> ownerIds;

  public PermissionService(BotConfig config) {
    this.ownerIds = config.runtime().ownerIds();
  }

  public boolean isOwner(Member member) {
    return member != null && ownerIds.contains(member.getIdLong());
  }

  public boolean hasAdminAccess(Member member, GuildSettings settings) {
    if (member == null) {
      return false;
    }
    if (isOwner(member)) {
      return true;
    }
    if (!settings.getAdminRoleIds().isEmpty() && hasAnyRole(member, settings.getAdminRoleIds())) {
      return true;
    }
    return settings.getAdminRoleIds().isEmpty() && member.hasPermission(Permission.MANAGE_SERVER);
  }

  public boolean hasSupportAccess(Member member, GuildSettings settings) {
    if (member == null) {
      return false;
    }
    if (hasAdminAccess(member, settings)) {
      return true;
    }
    if (!settings.getSupportRoleIds().isEmpty()
        && hasAnyRole(member, settings.getSupportRoleIds())) {
      return true;
    }
    return settings.getSupportRoleIds().isEmpty() && member.hasPermission(Permission.MANAGE_SERVER);
  }

  private boolean hasAnyRole(Member member, Set<Long> roleIds) {
    return member.getRoles().stream().anyMatch(role -> roleIds.contains(role.getIdLong()));
  }
}
