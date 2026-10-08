import 'package:flutter/services.dart';

/// Words in [text]: runs of non-whitespace, exactly what the server counts with `str.split()`.
/// Punctuation stays attached to its word, newlines and repeated spaces never add words.
int countWords(String text) => RegExp(r'\S+').allMatches(text).length;

/// Keeps a text field inside the Build My Day limit without ever editing the user's text.
///
/// An edit that would push the text past [maxWords] (or [maxChars], the backstop for text without spaces) is
/// refused and the previous value is kept, so a paste that does not fit is rejected whole rather than silently
/// cut. Text that is already over the limit (a prefilled dump) can still be deleted down.
class WordLimitFormatter extends TextInputFormatter {
  WordLimitFormatter({required this.maxWords, required this.maxChars, this.onRejected});

  final int maxWords;
  final int maxChars;

  /// Called with how many words the refused edit was over (at least 1 when only the character cap tripped).
  final void Function(int wordsOver)? onRejected;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final words = countWords(newValue.text);
    final tooManyWords = words > maxWords;
    final tooManyChars = newValue.text.length > maxChars;
    if (!tooManyWords && !tooManyChars) return newValue;
    // Shrinking toward the limit is always allowed.
    if (newValue.text.length <= oldValue.text.length && words <= countWords(oldValue.text)) return newValue;
    onRejected?.call(tooManyWords ? words - maxWords : 1);
    return oldValue;
  }
}
