enum CommandRegistrationMode {
  global,
  guild;

  static CommandRegistrationMode fromValue(String? value) {
    String normalized = value == null ? '' : value.trim().toUpperCase();
    return switch (normalized) {
      'GUILD' => CommandRegistrationMode.guild,
      _ => CommandRegistrationMode.global,
    };
  }
}
