package art.arcane.racbot.util;

import java.awt.Color;

public final class ColorParser {
  private ColorParser() {}

  public static Color parseHex(String color) {
    String normalized = color == null ? "" : color.trim();
    if (normalized.startsWith("#")) {
      normalized = normalized.substring(1);
    }
    return new Color(Integer.parseInt(normalized, 16));
  }
}
