import 'package:fast_log/fast_log.dart' as fast_log;

class AppLogger {
  final String scope;

  const AppLogger({required this.scope});

  void info(String message) {
    fast_log.info('[$scope] $message');
  }

  void warning(String message) {
    fast_log.warn('[$scope] $message');
  }

  void fine(String message) {
    fast_log.verbose('[$scope] $message');
  }

  void severe(String message, [Object? error, StackTrace? stackTrace]) {
    if (error == null) {
      fast_log.error('[$scope] $message');
      return;
    }

    fast_log.error('[$scope] $message ${error.runtimeType}: $error');
    if (stackTrace != null) {
      fast_log.error('[$scope] $stackTrace');
    }
  }
}
