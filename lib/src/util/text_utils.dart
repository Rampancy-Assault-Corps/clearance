class TextUtils {
  const TextUtils._();

  static String truncate({required String? value, required int maxLength}) {
    String text = value ?? '';
    if (text.trim().isEmpty) {
      return '';
    }
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength - 3)}...';
  }
}
