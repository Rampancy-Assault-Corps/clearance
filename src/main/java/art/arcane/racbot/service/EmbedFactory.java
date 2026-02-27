package art.arcane.racbot.service;

import art.arcane.racbot.config.BotConfig;
import art.arcane.racbot.util.ColorParser;
import java.time.Instant;
import net.dv8tion.jda.api.EmbedBuilder;

public class EmbedFactory {
  private final BotConfig config;

  public EmbedFactory(BotConfig config) {
    this.config = config;
  }

  public EmbedBuilder base(String title) {
    return new EmbedBuilder()
        .setTitle(title)
        .setColor(ColorParser.parseHex(config.branding().primaryColorHex()))
        .setFooter(config.branding().companyName(), config.branding().avatarUrl())
        .setTimestamp(Instant.now());
  }

  public EmbedBuilder info(String title, String description) {
    return base(title).setDescription(description);
  }

  public EmbedBuilder error(String title, String description) {
    return base(title).setDescription(":warning: " + description);
  }
}
