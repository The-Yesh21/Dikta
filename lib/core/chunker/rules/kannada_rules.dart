import 'language_rules.dart';

/// Kannada phrasing rules for handwriting dictation chunking.
class KannadaRules implements LanguageRules {
  const KannadaRules();

  @override
  Set<String> get neverEndOnWords => const {
        'ಮತ್ತು',
        'ಅಥವಾ',
        'ಈ',
        'ಆ',
        'ಒಂದು',
        'ಎಂಬ',
        'ಎಂದು',
        'ಹಾಗೂ',
        'ಎಲ್ಲಾ',
      };

  @override
  Set<String> get neverStartWithWords => const {
        'ನಲ್ಲಿ',
        'ಯಲ್ಲಿ',
        'ಯಿಂದ',
        'ಇಂದ',
        'ಗೆ',
        'ಕ್ಕೆ',
        'ಅನ್ನು',
        'ವನ್ನು',
      };

  @override
  Set<String> get goodBreakBeforeWords => const {
        'ಮತ್ತು',
        'ಹಾಗೂ',
        'ಅಥವಾ',
        'ಆದರೆ',
        'ಏಕೆಂದರೆ',
        'ಆದ್ದರಿಂದ',
        'ಹಾಗಾಗಿ',
        'ಯಾವಾಗ',
        'ಆಗ',
      };
}
