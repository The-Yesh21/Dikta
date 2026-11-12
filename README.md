# Dikta

A smart, rhythmic mobile dictation app designed to read study notes aloud at a human handwriting pace so students can copy them down by hand.

## Features
- **Pacing Engine**: Dynamic, fatigue-aware pacing with script-adaptive grapheme cluster timing (English/Latin, Hindi/Devanagari, Kannada).
- **TTS Synthesis**: Cloud-first MVP with Gnani AI multilingual TTS (caching audio chunks to minimize network and API usage), and offline fallback architecture.
- **Natural Boundary Pauses**: Configurable punctuation pauses for commas, sentences, and paragraphs, plus sawtooth rhythm breath recovery.
- **Handwriting Calibration**: Interactive stopwatch test to measure words/graphemes per second and tailor pacing to individual writing speed.
- **Live Tuning Panel**: Real-time slider controls for handwriting speed, speech rate, pauses, and fatigue compensation.
- **Tap-to-Advance**: Quick jump to the next chunk while adapting pace faster.
- **Session Audit & Logging**: Complete per-chunk diagnostics with copyable Markdown table output.
