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

/// [text] when it already reads like a sentence for people, otherwise [fallback]. For messages the server composed
/// for the user (plan confirm errors and the like) that must still never show internals if one slips through.
String plainOr(String text, String fallback) => isPlainSentence(text) ? text.trim() : fallback;

const String _connectionCopy = "I can't reach Flowstate right now. Check your connection and try again.";

/// Calm copy for any failed action outside Replan (a purchase, a sync, an account request). A server message is shown
/// only when it already reads like a sentence for people; everything else maps to fixed text. Never an exception name,
/// an HTTP status, JSON, a provider name or a stack trace. [fallback] is what the caller wants said for the unknown.
String friendlyActionError(Object e, {String fallback = 'Something went wrong. Please try again in a moment.'}) {
  if (e is ApiException) {
    final detail = e.data is Map<String, dynamic> ? (e.data as Map<String, dynamic>)['detail'] : null;
    String? candidate;
    if (detail is String) {
      candidate = detail;
    } else if (detail is Map<String, dynamic> && detail['message'] is String) {
      candidate = detail['message'] as String;
    }
    if (candidate != null && isPlainSentence(candidate)) return candidate.trim();
    if (e.isTimeout) return 'That took longer than expected. Please try again.';
    final code = e.statusCode;
    if (code == null || code == 0) return _connectionCopy;
    if (code == 401) return 'Please sign in again to continue.';
    if (code == 402 || code == 429) return "You've reached the limit for now. Please try again a little later.";
    if (code == 422) return "That didn't look right. Please check it and try again.";
    if (code >= 500) return "Flowstate couldn't finish that just now. Please try again in a moment.";
    return fallback;
  }
  final text = e.toString().toLowerCase();
  if (text.contains('network') || text.contains('socket') || text.contains('connection')) return _connectionCopy;
  return fallback;
}

/// Sign-in / sign-up failures: the known provider messages become plain sentences, other plain sentences pass, and
/// anything technical becomes [fallback].
String friendlyAuthMessage(
  Object e, {
  String fallback = "We couldn't sign you in right now. Please check your email, password and connection, then try again.",
}) {
  if (e is ApiException) return friendlyActionError(e, fallback: fallback);
  final msg = e.toString().replaceAll('Exception:', '').trim();
  if (msg.contains('Invalid login credentials') || msg.contains('invalid_credentials')) {
    return 'Invalid email or password. Please try again.';
  }
  if (msg.contains('User already registered') || msg.contains('user_already_exists')) {
    return 'Account already exists. Please log in instead.';
  }
  if (msg.contains('Email not confirmed') || msg.contains('email_not_confirmed')) {
    return 'Please check your email and verify your account before logging in.';
  }
  if (msg.contains('over_email_send_rate_limit') || msg.contains('rate limit')) {
    return 'Email rate limit reached. Please wait a few minutes before trying again.';
  }
  final lower = msg.toLowerCase();
  if (lower.contains('socket') || lower.contains('network') || lower.contains('connection')) return _connectionCopy;
  return plainOr(msg, fallback);
}
