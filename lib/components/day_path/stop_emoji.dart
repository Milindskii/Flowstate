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
  (['admin', 'light'], '📧'),
  (['rest', 'break'], '😴'),
  (['personal', 'life', 'home'], '🌿'),
  (['social'], '💛'),
  (['creative'], '🎨'),
];
