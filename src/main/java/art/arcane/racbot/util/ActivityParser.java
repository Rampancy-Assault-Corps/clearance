package art.arcane.racbot.util;

import net.dv8tion.jda.api.entities.Activity;

public final class ActivityParser {
  private ActivityParser() {}

  public static Activity parse(String value) {
    String raw = value == null ? "" : value.trim();
    if (raw.isBlank()) {
      return Activity.watching("support channels");
    }

    String[] split = raw.split(":", 2);
    if (split.length == 2) {
      String kind = split[0].trim().toLowerCase();
      String text = split[1].trim();
      return switch (kind) {
        case "playing" -> Activity.playing(text);
        case "listening" -> Activity.listening(text);
        case "watching" -> Activity.watching(text);
        case "competing" -> Activity.competing(text);
        default -> Activity.watching(raw);
      };
    }

    return Activity.watching(raw);
  }
}
