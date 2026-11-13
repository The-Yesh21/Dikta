/// Age group categories for handwriting speed priors.
enum AgeGroup {
  age8to10('8-10', 30.0),
  age11to13('11-13', 45.0),
  age14to17('14-17', 60.0),
  age18Plus('18+', 60.0);

  const AgeGroup(this.label, this.priorLpm);

  /// Human-readable label for UI display (e.g. '8-10', '18+').
  final String label;

  /// Baseline prior handwriting speed in letters per minute (LPM).
  final double priorLpm;

  /// Effective starting LPM accounting for dictation cognitive/listening overhead.
  ///
  /// Formula: effective starting lpm = prior * dictationFactor (default 0.8).
  double effectiveStartingLpm([double dictationFactor = PacingPriors.defaultDictationFactor]) {
    return priorLpm * dictationFactor;
  }
}

/// Baseline handwriting priors and sources by age group.
///
/// DOCUMENTATION OF SOURCES (MARK AS PLACEHOLDER):
/// All values below are initial empirical estimates and literature-derived placeholders
/// pending field validation with student cohorts across English, Hindi, and Kannada.
///
/// 1. Age 8-10 (approx. Grades 3-5): 30 LPM (letters per minute).
///    - Source / Literature: Graham, S., Berninger, V., Weintraub, N., & Schafer, W. (1998).
///      "Development of handwriting speed and legibility in elementary school".
///    - Baseline: Typical copy speed ~25-35 letters/min.
///    - Status: [PLACEHOLDER] - requires empirical calibration for South Asian languages and mobile dictation.
///
/// 2. Age 11-13 (approx. Grades 6-8): 45 LPM.
///    - Source / Literature: Wallen, M., Mackay, S., & Broadbent, J. (1996);
///      Amundson, S. J. Evaluation Tool of Children's Handwriting (ETCH).
///    - Baseline: Middle school copy speed ~40-50 letters/min.
///    - Status: [PLACEHOLDER] - requires empirical calibration.
///
/// 3. Age 14-17 (High School): 60 LPM.
///    - Source / Literature: Roebers, C. M., & Kauer, M. (2009);
///      Sustained classroom copying norms for high school students: ~55-65 letters/min.
///    - Baseline: Secondary students copy at ~60 LPM.
///    - Status: [PLACEHOLDER] - requires empirical calibration.
///
/// 4. Age 18+ (Adult / Higher Education): 60 LPM.
///    - Source / Literature: Ziviani, J., & Watson-Will, A. (1998).
///      Adult sustained handwriting speed plateaus at approximately 60-70 letters/min under copy conditions.
///    - Baseline: ~60 LPM.
///    - Status: [PLACEHOLDER] - requires empirical calibration.
///
/// DICTATION FACTOR (default 0.8):
/// In audio dictation, listening comprehension, acoustic buffer retention, and cognitive
/// load reduce handwritten copying output by approximately 20% compared to direct visual copy.
/// Effective starting LPM = prior * dictationFactor (e.g. 60 * 0.8 = 48.0 LPM).
class PacingPriors {
  const PacingPriors._();

  /// Default factor applied to prior LPM to account for dictation listening/cognitive overhead (0.8).
  static const double defaultDictationFactor = 0.8;

  /// Map of AgeGroup to baseline prior LPM.
  static const Map<AgeGroup, double> priorsByAge = {
    AgeGroup.age8to10: 30.0,
    AgeGroup.age11to13: 45.0,
    AgeGroup.age14to17: 60.0,
    AgeGroup.age18Plus: 60.0,
  };

  /// Returns baseline prior LPM for the given [ageGroup].
  static double getPriorLpm(AgeGroup ageGroup) {
    return ageGroup.priorLpm;
  }

  /// Returns the effective starting LPM for the given [ageGroup] adjusted by [dictationFactor].
  ///
  /// Effective starting lpm = prior * dictationFactor.
  static double getEffectiveStartingLpm(
    AgeGroup ageGroup, {
    double dictationFactor = defaultDictationFactor,
  }) {
    return ageGroup.effectiveStartingLpm(dictationFactor);
  }
}
