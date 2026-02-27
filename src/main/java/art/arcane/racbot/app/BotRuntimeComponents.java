package art.arcane.racbot.app;

import art.arcane.racbot.config.BotConfig;
import art.arcane.racbot.service.EmbedFactory;
import art.arcane.racbot.service.PermissionService;
import art.arcane.racbot.service.SetupService;

public record BotRuntimeComponents(
    BotConfig config,
    SetupService setupService,
    PermissionService permissionService,
    EmbedFactory embedFactory) {}
