package art.arcane.racbot.app;

import art.arcane.racbot.config.BotConfig;
import art.arcane.racbot.service.EmbedFactory;

public record BotRuntimeComponents(
    BotConfig config, EmbedFactory embedFactory) {}
