package art.arcane.racbot.service;

import art.arcane.racbot.model.GuildSettings;
import java.util.List;

public record SetupProvisionResult(GuildSettings settings, List<String> actions) {}
