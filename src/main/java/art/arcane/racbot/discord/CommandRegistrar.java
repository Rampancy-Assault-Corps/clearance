package art.arcane.racbot.discord;

import art.arcane.racbot.config.BotConfig;
import art.arcane.racbot.config.CommandRegistrationMode;
import java.util.ArrayList;
import java.util.List;
import net.dv8tion.jda.api.JDA;
import net.dv8tion.jda.api.entities.Guild;
import net.dv8tion.jda.api.interactions.commands.build.CommandData;
import net.dv8tion.jda.api.interactions.commands.build.Commands;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class CommandRegistrar {
  private static final Logger LOGGER = LoggerFactory.getLogger(CommandRegistrar.class);

  private final BotConfig config;

  public CommandRegistrar(BotConfig config) {
    this.config = config;
  }

  public void register(JDA jda) {
    List<CommandData> commands = buildCommands();
    if (commands.isEmpty()) {
      LOGGER.warn("No commands enabled. Skipping slash command registration.");
      return;
    }

    if (config.bot().commandRegistrationMode() == CommandRegistrationMode.GUILD
        && config.bot().devGuildId() != null) {
      Guild guild = jda.getGuildById(config.bot().devGuildId());
      if (guild != null) {
        guild.updateCommands().addCommands(commands).queue();
        LOGGER.info("Registered {} commands in dev guild {}", commands.size(), guild.getId());
        return;
      }
      LOGGER.warn(
          "Configured dev guild {} not found, falling back to global command registration.",
          config.bot().devGuildId());
    }

    jda.updateCommands().addCommands(commands).queue();
    LOGGER.info("Registered {} commands globally.", commands.size());
  }

  private List<CommandData> buildCommands() {
    List<CommandData> commands = new ArrayList<>();

    if (config.features().pingEnabled()) {
      commands.add(Commands.slash("ping", "Check bot latency"));
    }

    return commands;
  }
}
