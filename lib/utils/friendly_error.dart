import '../services/api_service.dart';

/// Plain Flowstate language for any failed request: never raw JSON, field or code names, HTTP statuses,
/// provider/model names or stack traces. A server message is shown only when it already reads like a sentence
/// meant for people; otherwise the status class picks a calm, fixed explanation.
String friendlyErrorMessage(
  Object e, {
  String fallback = "Something went wrong on my side. Your message is still here, so you can try again.",
}) {
  if (e is ApiException) {
    final detail = e.data is Map<String, dynamic> ? (e.data as Map<String, dynamic>)['detail'] : null;
    String? candidate;
    if (detail is Map<String, dynamic>) {
      final errs = detail['errors'];
      if (errs is List && errs.isNotEmpty && errs.first is Map && (errs.first as Map)['message'] is String) {
        candidate = (errs.first as Map)['message'] as String;
      } else if (detail['message'] is String) {
        candidate = detail['message'] as String;
      }
    } else if (detail is String) {
      candidate = detail;
    }
    if (candidate != null && isPlainSentence(candidate)) return candidate;
    final code = e.statusCode;
    if (code == 401) return 'Please sign in again and we will pick up where you left off.';
    if (code == 402 || code == 429) return "You've reached today's planning limit. Try again a little later.";
    if (code == 422) {
      return "I couldn't read that change. Try rephrasing it, for example “skip gym” or “move essay to Friday”.";
    }
    if (code != null && code >= 500) {
      return "Noya couldn't reach your plan just now. Your message is still here, so try again in a moment.";
    }
  }
  final text = e.toString().toLowerCase();
  if (text.contains('network') || text.contains('socket') || text.contains('connection')) {
    return "I can't reach Flowstate right now. Check your connection — your message is still here.";
  }
  return fallback;
}

// Signals of internal text: braces/brackets, `code:` / `field:` style keys, stack/exception words, provider
// names, HTTP/JSON jargon and snake_case identifiers. Everyday words like "status" or "model" are fine.
final RegExp _internalText = RegExp(
  r'[{}\[\]]|\b(code|field|detail)\s*:|traceback|exception|gemini|openai|anthropic|https?|json|\bnull\b|\b[a-z]+_[a-z_]+\b|\b\d{3}\b',
  caseSensitive: false,
);

/// True when [text] is short, human-readable and free of internal identifiers.
bool isPlainSentence(String text) {
  final t = text.trim();
  return t.isNotEmpty && t.length < 220 && !_internalText.hasMatch(t);
}
