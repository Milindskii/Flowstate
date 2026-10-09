import 'package:flutter/material.dart';

/// A small, deterministic picture for a Calendar stop, so the road reads at a glance ("🧠 ML assignment",
/// "🏫 Class", "🏋️ Gym").
///
/// Chosen from the task's own words first (title), then its category / type, then a neutral pin. The same task always
/// gets the same emoji: no randomness, no dependence on order or time, so a rebuild never changes it.
String stopEmojiFor({required String title, String? category, String? type}) {
  final t = ' ${title.toLowerCase()} ';
  for (final (words, emoji) in _byTitle) {
    for (final w in words) {
      if (t.contains(w)) return emoji;
    }
  }
  final c = '${category ?? ''} ${type ?? ''}'.toLowerCase();
  for (final (words, emoji) in _byCategory) {
    for (final w in words) {
      if (c.contains(w)) return emoji;
    }
  }
  return '📌';
}

// Ordered: the first match wins, so the more specific words come first.
const List<(List<String>, String)> _byTitle = [
  (['gym', 'workout', 'work out', 'lift', 'exercise', 'training', 'cardio'], '🏋️'),
  ([' run ', 'running', 'jog'], '🏃'),
  (['yoga', 'meditat', 'stretch'], '🧘'),
  (['walk'], '🚶'),
  (['swim'], '🏊'),
  (['class', 'lecture', 'school', 'college', 'tutorial', 'lab '], '🏫'),
  (['assignment', 'homework', ' ml ', 'machine learning', 'dsa', 'algorithm', 'problem set', 'revision', 'revise'], '🧠'),
  (['exam', 'test prep', 'quiz'], '📝'),
  (['study', 'learn', 'course'], '📚'),
  (['read', 'book'], '📖'),
  (['write', 'essay', 'blog', 'journal'], '✍️'),
  (['code', 'coding', 'program', 'debug', 'deploy', 'build ', 'app '], '💻'),
  (['meeting', 'standup', 'stand-up', 'sync', 'interview'], '👥'),
  (['call', 'phone'], '📞'),
  (['email', 'inbox', 'admin', 'paperwork', 'invoice', 'tax'], '📧'),
  (['plan', 'review', 'organize', 'organise'], '🗂️'),
  (['breakfast', 'lunch', 'dinner', 'meal', 'cook', 'eat'], '🍽️'),
  (['groceries', 'grocery', 'shop'], '🛒'),
  (['clean', 'laundry', 'chores', 'tidy'], '🧹'),
  (['doctor', 'dentist', 'clinic', 'hospital', 'medic', 'therapy'], '🩺'),
  (['commute', 'travel', 'flight', 'train', 'bus', 'drive'], '🚌'),
  (['music', 'guitar', 'piano', 'practice', 'sing'], '🎵'),
  (['sleep', 'nap', 'rest', 'break'], '😴'),
  (['family', 'friend', 'date', 'party'], '💛'),
  (['design', 'draw', 'paint', 'sketch'], '🎨'),
  (['work', 'project', 'deep work', 'focus'], '💼'),
];

const List<(List<String>, String)> _byCategory = [
  (['fitness', 'physical', 'health', 'sport'], '🏋️'),
  (['study', 'learning', 'education', 'medium'], '📚'),
  (['deep', 'high focus', 'work'], '💼'),
  (['light'], '📧'),
  (['rest', 'break'], '😴'),
  (['personal', 'life', 'home', 'admin'], '🌿'),
  (['social'], '💛'),
  (['creative'], '🎨'),
];

/// The themed picture for a stop: a rounded line icon in the caller's colour instead of a platform emoji, so the road
/// looks the same on every device and takes the ring / accent colour of its state. Derived from [stopEmojiFor], so the
/// choice stays deterministic and the two never disagree.
IconData stopIconFor({required String title, String? category, String? type}) =>
    _iconByEmoji[stopEmojiFor(title: title, category: category, type: type)] ?? Icons.place_rounded;

const Map<String, IconData> _iconByEmoji = {
  '🏋️': Icons.fitness_center_rounded,
  '🏃': Icons.directions_run_rounded,
  '🧘': Icons.self_improvement_rounded,
  '🚶': Icons.directions_walk_rounded,
  '🏊': Icons.pool_rounded,
  '🏫': Icons.school_rounded,
  '🧠': Icons.psychology_rounded,
  '📝': Icons.edit_note_rounded,
  '📚': Icons.menu_book_rounded,
  '📖': Icons.auto_stories_rounded,
  '✍️': Icons.edit_rounded,
  '💻': Icons.code_rounded,
  '👥': Icons.groups_rounded,
  '📞': Icons.call_rounded,
  '📧': Icons.mail_rounded,
  '🗂️': Icons.folder_open_rounded,
  '🍽️': Icons.restaurant_rounded,
  '🛒': Icons.shopping_cart_rounded,
  '🧹': Icons.cleaning_services_rounded,
  '🩺': Icons.medical_services_rounded,
  '🚌': Icons.directions_bus_rounded,
  '🎵': Icons.music_note_rounded,
  '😴': Icons.bedtime_rounded,
  '💛': Icons.favorite_rounded,
  '🎨': Icons.palette_rounded,
  '💼': Icons.work_rounded,
  '🌿': Icons.spa_rounded,
  '📌': Icons.place_rounded,
};
