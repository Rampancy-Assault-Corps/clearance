package art.arcane.racbot.service;

import java.util.List;

public record SetupAuditResult(boolean healthy, List<String> findings) {}
