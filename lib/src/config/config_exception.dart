class ConfigException implements Exception {
  final String message;
  final Object? cause;

  const ConfigException({required this.message, this.cause});

  @override
  String toString() => cause == null ? message : '$message (cause: $cause)';
}
