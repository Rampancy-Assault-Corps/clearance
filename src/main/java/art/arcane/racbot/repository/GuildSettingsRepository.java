package art.arcane.racbot.repository;

import art.arcane.racbot.model.GuildSettings;
import java.util.Optional;

public interface GuildSettingsRepository {
  Optional<GuildSettings> findByGuildId(long guildId);

  GuildSettings save(GuildSettings settings);
}
