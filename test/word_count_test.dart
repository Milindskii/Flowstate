import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/utils/word_count.dart';

String words(int n) => List.filled(n, 'word').join(' ');

void main() {
  group('countWords', () {
    test('empty and whitespace-only text has no words', () {
      expect(countWords(''), 0);
      expect(countWords('   \n\t  '), 0);
    });

    test('counts runs of non-whitespace, like the server (str.split)', () {
      expect(countWords('buy milk'), 2);
      expect(countWords('  buy   milk  '), 2);
      expect(countWords('buy\nmilk\n\nand\teggs'), 4);
    });

    test('punctuation stays attached and creates no extra words', () {
      expect(countWords('Gym, 6pm; then... dinner!'), 4);
      expect(countWords('well-known e-mail (draft)'), 3);
    });

    test('bullets and emoji count as the user typed them', () {
      expect(countWords('- one\n- two'), 4);
      expect(countWords('🏋️ gym'), 2);
    });

    test('a long unbroken run is one word', () {
      expect(countWords('字' * 500), 1);
    });
  });

  group('WordLimitFormatter', () {
    TextEditingValue v(String t) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

    test('allows text up to the limit', () {
      final f = WordLimitFormatter(maxWords: 5, maxChars: 100);
      expect(f.formatEditUpdate(v(''), v(words(5))).text, words(5));
    });

    test('rejects an edit that would pass the limit and keeps the old text', () {
      final f = WordLimitFormatter(maxWords: 5, maxChars: 100);
      final old = v(words(5));
      expect(f.formatEditUpdate(old, v('${words(5)} more')).text, old.text);
    });

    test('typing a space after the last allowed word is fine', () {
      final f = WordLimitFormatter(maxWords: 5, maxChars: 100);
      expect(f.formatEditUpdate(v(words(5)), v('${words(5)} ')).text, '${words(5)} ');
    });

    test('a paste that does not fit is rejected whole, never truncated, and reports the overflow', () {
      int? over;
      final f = WordLimitFormatter(maxWords: 10, maxChars: 1000, onRejected: (n) => over = n);
      final old = v(words(4));
      final result = f.formatEditUpdate(old, v('${words(4)} ${words(20)}'));
      expect(result.text, old.text);
      expect(over, 14);
    });

    test('a paste that fits is accepted', () {
      final f = WordLimitFormatter(maxWords: 10, maxChars: 1000);
      expect(f.formatEditUpdate(v(words(4)), v('${words(4)} ${words(6)}')).text, '${words(4)} ${words(6)}');
    });

    test('the character backstop applies to text without spaces', () {
      final f = WordLimitFormatter(maxWords: 450, maxChars: 50);
      final old = v('字' * 40);
      expect(f.formatEditUpdate(old, v('字' * 60)).text, old.text);
    });

    test('text already over the limit (prefilled) may be deleted down', () {
      final f = WordLimitFormatter(maxWords: 5, maxChars: 100);
      final old = v(words(9));
      expect(f.formatEditUpdate(old, v(words(8))).text, words(8));
    });
  });
}
