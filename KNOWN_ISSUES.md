# Known Issues & Future Refinements

This document records linguistic edge cases and formula considerations identified during Phase 1 that are deferred to later listening evaluations.

## 1. Chunker Phrasing Edge Cases

### English
- **Adjective-Noun & Compound Splits:**
  - In long sentences without punctuation, greedy or scored boundary selection can occasionally split tightly bound noun phrases or modifier pairs (e.g. `electrochemical proton / gradient`, `inner / mitochondrial membrane`).
  - *Mitigation:* To be evaluated by ear during Step 7 listening tests. Can introduce a lightweight POS tagger or compound noun dictionary if splits sound unnatural.

### Hindi (Devanagari)
- **Fixed Phrases & Scientific Compounds:**
  - Multi-word compound idioms and scientific loan translations (e.g. `मुख्य / रूप से` [primarily], `थाइलाकोइड / झिल्ली` [thylakoid membrane]) may occasionally be split across chunk boundaries.
  - *Mitigation:* To be audited after hearing the Hindi TTS voice cadence in Phase 4.

### Kannada
- **Genitive Suffix Splitting:**
  - Chunks occasionally terminate on a genitive inflected noun (endings such as `-ನ`, `-ದ`, `-ಯ`, `-ಿನ`) where the possessed noun starts the subsequent chunk (e.g. `...ಸೂರ್ಯನ` / `ಕಿರಣಗಳನ್ನು...`, `...ಹರಿದ್ರೇಣುವಿನ` / `ಸ್ಟ್ರೋಮಾದಲ್ಲಿ`).
  - *Mitigation:* Suffix matching can be added after native speaker audio review.

---

## 2. Pacing Engine Formula Considerations

### Multiplicative vs Additive Syntax Factors
- **Current Formula:**
  ```text
  gap = (n_words / writing_speed) / tempo(t) * syntax_factor * jitter - speech_duration
  ```
- **Observation:**
  - Because `syntax_factor` (e.g. 1.8 for sentences, 2.5 for paragraphs) multiplies the entire calculated writing duration, longer chunks produce extended silence pauses (e.g. 25–40+ seconds).
  - A human dictator typically adds a small distinct extra beat at major boundaries rather than scaling the entire handwriting time by 80% to 150%.
- **Planned Refinement:**
  - Evaluate this directly by ear during end-to-end dictation in Step 7.
  - If idle pauses feel excessive when copying notes by hand, consider converting syntax factors to additive pauses (e.g. +0.5s for commas, +2.0s for sentence boundaries, +3.5s for paragraph transitions) on top of the base handwriting window.
