import 'language_rules.dart';

/// English phrasing rules for handwriting dictation chunking.
class EnglishRules implements LanguageRules {
  const EnglishRules();

  @override
  Set<String> get neverEndOnWords => const {
        // Articles & determiners
        'a',
        'an',
        'the',
        'its',
        'their',
        'his',
        'her',
        'our',
        'my',
        'your',
        'this',
        'that',
        'these',
        'those',

        // Prepositions
        'of',
        'in',
        'on',
        'at',
        'to',
        'for',
        'with',
        'by',
        'from',
        'into',
        'across',
        'as',
        'through',
        'over',
        'under',
        'between',
        'among',
        'without',
        'within',

        // Conjunctions & relatives
        'and',
        'or',
        'but',
        'nor',
        'so',
        'yet',
        'which',
        'where',
        'when',
        'while',
        'because',
        'if',
        'although',
        'though',

        // Copula, auxiliary verbs & modals
        'is',
        'are',
        'was',
        'were',
        'be',
        'been',
        'being',
        'has',
        'have',
        'had',
        'would',
        'could',
        'should',
        'can',
        'will',
        'may',
        'might',
        'must',
      };

  @override
  Set<String> get neverStartWithWords => const {};

  @override
  Set<String> get goodBreakBeforeWords => const {
        'and',
        'or',
        'but',
        'because',
        'although',
        'though',
        'since',
        'while',
        'whereas',
        'which',
        'where',
        'when',
        'who',
        'whom',
        'whose',
        'that',
        'if',
        'unless',
        'whether',
        'so',
      };
}
