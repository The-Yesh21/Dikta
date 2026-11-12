import 'english_rules.dart';
import 'hindi_rules.dart';
import 'kannada_rules.dart';
import 'language_rules.dart';

/// Registry and auto-detector for language phrasing rules.
class LanguageRulesRegistry {
  static const EnglishRules english = EnglishRules();
  static const HindiRules hindi = HindiRules();
  static const KannadaRules kannada = KannadaRules();

  /// Automatically selects phrasing rules based on Unicode character ranges in [text].
  static LanguageRules detect(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x0C80 && rune <= 0x0CFF) {
        return kannada;
      }
      if (rune >= 0x0900 && rune <= 0x097F) {
        return hindi;
      }
    }
    return english;
  }
}
