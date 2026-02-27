package art.arcane.racbot.repository.json;

import art.arcane.racbot.model.GuildSettings;
import art.arcane.racbot.repository.GuildSettingsRepository;
import java.nio.file.Path;
import java.util.Optional;

public class JsonGuildSettingsRepository extends JsonRepositorySupport
    implements GuildSettingsRepository {

  public JsonGuildSettingsRepository(Path dataRoot, boolean atomicWrites) {
    super(dataRoot, atomicWrites);
  }

  @Override
  public Optional<GuildSettings> findByGuildId(long guildId) {
    return read(pathFor(guildId), GuildSettings.class)
        .map(
            settings -> {
              if (settings.getGuildId() == 0L) {
                settings.setGuildId(guildId);
              }
              return settings;
            });
  }

  @Override
  public GuildSettings save(GuildSettings settings) {
    settings.touch();
    return write(pathFor(settings.getGuildId()), settings);
  }

  private Path pathFor(long guildId) {
    return dataRoot().resolve("guilds").resolve(Long.toString(guildId)).resolve("settings.json");
  }
}
