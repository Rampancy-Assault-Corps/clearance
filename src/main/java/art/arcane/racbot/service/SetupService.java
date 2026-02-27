package art.arcane.racbot.service;

import art.arcane.racbot.config.BotConfig;
import art.arcane.racbot.model.GuildSettings;
import art.arcane.racbot.repository.GuildSettingsRepository;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import net.dv8tion.jda.api.entities.Guild;
import net.dv8tion.jda.api.entities.Role;

public class SetupService {
  private final BotConfig config;
  private final GuildSettingsRepository guildSettingsRepository;

  public SetupService(BotConfig config, GuildSettingsRepository guildSettingsRepository) {
    this.config = config;
    this.guildSettingsRepository = guildSettingsRepository;
  }

  public GuildSettings getOrCreateSettings(long guildId) {
    return guildSettingsRepository
        .findByGuildId(guildId)
        .map(
            settings -> {
              settings.touch();
              return settings;
            })
        .orElseGet(() -> GuildSettings.create(guildId));
  }

  public SetupProvisionResult provision(Guild guild) {
    GuildSettings settings = getOrCreateSettings(guild.getIdLong());
    List<String> actions = new ArrayList<>();

    Role adminRole =
        ensureRole(
            guild, settings.getAdminRoleIds(), config.guildDefaults().adminRoleName(), actions);
    Role supportRole =
        ensureRole(
            guild, settings.getSupportRoleIds(), config.guildDefaults().supportRoleName(), actions);

    settings.setAdminRoleIds(new LinkedHashSet<>(Set.of(adminRole.getIdLong())));
    settings.setSupportRoleIds(new LinkedHashSet<>(Set.of(supportRole.getIdLong())));
    settings.touch();

    guildSettingsRepository.save(settings);
    if (actions.isEmpty()) {
      actions.add("No changes needed. Resources were already aligned.");
    }

    return new SetupProvisionResult(settings, actions);
  }

  public SetupAuditResult audit(Guild guild) {
    Optional<GuildSettings> existing = guildSettingsRepository.findByGuildId(guild.getIdLong());
    if (existing.isEmpty()) {
      return new SetupAuditResult(
          false, List.of("No guild settings found. Run /setup provision first."));
    }

    GuildSettings settings = existing.get();
    List<String> findings = new ArrayList<>();

    if (resolveRoleByIds(guild, settings.getAdminRoleIds()).isEmpty()) {
      findings.add("Missing admin role assignment from stored guild settings.");
    }
    if (resolveRoleByIds(guild, settings.getSupportRoleIds()).isEmpty()) {
      findings.add("Missing support role assignment from stored guild settings.");
    }

    if (findings.isEmpty()) {
      findings.add("Audit passed. All managed resources are present.");
      return new SetupAuditResult(true, findings);
    }

    return new SetupAuditResult(false, findings);
  }

  private Role ensureRole(Guild guild, Set<Long> roleIds, String roleName, List<String> actions) {
    Optional<Role> roleById = resolveRoleByIds(guild, roleIds);
    Role role =
        roleById.orElseGet(
            () -> guild.getRolesByName(roleName, true).stream().findFirst().orElse(null));

    if (role == null) {
      Role created = guild.createRole().setName(roleName).complete();
      actions.add("Created role: " + roleName);
      return created;
    }

    if (!Objects.equals(role.getName(), roleName)) {
      role.getManager().setName(roleName).complete();
      actions.add("Renamed role to: " + roleName);
    }

    return role;
  }

  private Optional<Role> resolveRoleByIds(Guild guild, Set<Long> roleIds) {
    for (Long roleId : roleIds) {
      Role role = guild.getRoleById(roleId);
      if (role != null) {
        return Optional.of(role);
      }
    }
    return Optional.empty();
  }
}
