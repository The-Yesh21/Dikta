import 'language_rules.dart';

/// Hindi (Devanagari) phrasing rules for handwriting dictation chunking.
class HindiRules implements LanguageRules {
  const HindiRules();

  @override
  Set<String> get neverEndOnWords => const {
        // Genitive markers / postpositions
        'का',
        'के',
        'की',

        // Demonstratives & articles
        'इस',
        'उस',
        'यह',
        'वह',
        'ये',
        'वे',
        'एक',

        // Conjunctions & relative markers
        'और',
        'या',
        'तथा',
        'एवं',
        'कि',
        'जो',
        'जिस',
        'जिन्हें',
        'जिससे',
        'जिसमें',
      };

  @override
  Set<String> get neverStartWithWords => const {
        // Postpositions (vibhakti markers) that must attach to the preceding noun
        'से',
        'में',
        'को',
        'पर',
        'का',
        'के',
        'की',
        'तक',
        'द्वारा',
        'हेतु',
        'लिए',
      };

  @override
  Set<String> get goodBreakBeforeWords => const {
        // Conjunctions & clause starters
        'और',
        'तथा',
        'एवं',
        'या',
        'अथवा',
        'लेकिन',
        'किन्तु',
        'परन्तु',
        'मगर',
        'क्योंकि',
        'इसलिए',
        'ताकि',
        'जिससे',
        'जिसमें',
        'जिसके',
        'जिन्हें',
        'जब',
        'तब',
        'यदि',
        'अगर',
      };
}
