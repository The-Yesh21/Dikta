/// Abstract interface for language-specific chunking and phrasing rules.
abstract class LanguageRules {
  /// Tokens that a chunk should strongly avoid ending on (e.g. prepositions, articles).
  Set<String> get neverEndOnWords;

  /// Tokens that a chunk should strongly avoid starting with (e.g. postpositions).
  Set<String> get neverStartWithWords;

  /// Tokens where breaking immediately before them creates natural, rhythmic phrasing
  /// (e.g. coordinating conjunctions, relative pronouns).
  Set<String> get goodBreakBeforeWords;
}
