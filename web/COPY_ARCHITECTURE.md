# Dikta Landing Page — Unslop Copy & Content Architecture
## For `web/index.html`

Derived from `01_PROJECT_OVERVIEW.md`, `02_SCOPE_AND_NON_GOALS.md`, `03_TECH_STACK.md`, and the Unslop Craft Framework.

---

### Unslop Direction
- **Product:** Dictation and handwriting companion for students and learners copying notes.
- **Character:** Scholarly, calm, exact, tactile.
- **World:** Oxford study, archival manuscript binder, gold-leaf foil, ruled notebook parchment, dark burgundy ink.
- **Moments:** 
  1. An interactive Dikta Notebook phrase card demonstrating active cadence playback, gold equalizer sound wave, pedagogical syllable spelling chips, and a working countdown.
  2. The fatigue decay & sawtooth curve graph showing writing energy recovery at paragraph breaks.
- **Signature:** Archival ruled-line margins with gold hairline annotations and exact grapheme timing equations (`t = 0.28s / grapheme`).

---

### Color Palette Tokens (from `dikta_theme.dart`)
- **Burgundy Deep (Wine):** `#3F0B13`
- **Burgundy Primary (Royal):** `#5B101E`
- **Burgundy Medium (Crimson):** `#7B1728`
- **Crimson Accent:** `#9E2336`
- **Antique Gold Accent:** `#C5A059`
- **Radiant Gold Leaf:** `#DFB15B`
- **Parchment Background:** `#FAF7F2`
- **Card Surface:** `#FFFFFF`
- **Ink Primary:** `#221316`
- **Ink Secondary:** `#5C474D`
- **Ink Muted:** `#8F7B81`
- **Border Hairline:** `#EADBCE`
- **Antique Gold Border:** `#E2D0A6`

---

## 1. Header & Navigation

- **Wordmark:**
  - Label: `Dikta`
  - Descriptor / Tag: `Archival Dictation`
- **Nav Links:**
  - Link 1: `The problem` (`#problem`)
  - Link 2: `Pacing engine` (`#pacing`)
  - Link 3: `Spelling method` (`#spelling`)
  - Link 4: `PDF & diagrams` (`#pdf`)
  - Link 5: `Trilingual` (`#trilingual`)
- **Header Action:**
  - Button text: `Download APK` (`#download`)

---

## 2. Hero Section

- **Eyebrow / Kicker:**
  - Text: `Handwriting companion for students`
- **Headline (H1):**
  - Text: `Notes read aloud at the rhythm of handwriting`
- **Subheadline:**
  - Text: `Standard text readers speak continuously. Dikta divides lecture notes, textbooks, and PDFs into short grammatical phrases with calibrated handwriting pauses, letting your pen keep pace without touching the screen.`
- **Actions:**
  - Primary CTA Button: `Download Dikta for Android (.apk)`
    - Link: `app-debug.apk`
    - Subtext / Metadata pill: `Version 1.0.0 · 245 MB · Android 8.0+`
  - Secondary Button: `Try pacing simulator`
    - Link: `#simulator`
- **Spec / Assurance Bar:**
  - Item 1: `On-device keyword spotting`
  - Item 2: `Airplane mode verified`
  - Item 3: `Zero cloud accounts or analytics`

---

## 3. Interactive Hero Moment: The Dikta Pacing Simulator (`#simulator`)

A working, tactile HTML/JS component embedded directly on the page.

- **Card Header:**
  - Document Title: `Active note: Biology 101 · Cellular respiration`
  - Phrase Index: `Phrase 3 of 12`
  - Status Pill: `Pacing locked: 48 LPM`
- **Main Phrase Display:**
  - Spoken Text: `"Mitochondria produce adenosine triphosphate,"`
  - Punctuation Marker: `[Comma boundary · 1.2x pause factor]`
- **Pedagogical Syllable Spelling Box:**
  - Label: `Teacher's spelling aid`
  - Chips:
    - Chip 1: `M · I · T · O  (mito)`
    - Chip 2: `C · H · O · N · D · R · I · A  (mitochondria)`
- **Equalizer & Gap Rhythm:**
  - Sound wave visualizer: 5 vertical gold equalizer bars (`#C5A059`) with gentle CSS animation during speech.
  - Pause Countdown:
    - State: `Writing gap: 4.8 seconds remaining`
    - Visual progress: Ruled notebook line progress indicator filling smoothly.
- **Tactile Control Buttons:**
  - Button 1: `⟲ Repeat phrase`
  - Button 2: `⏸ Pause` / `▶ Resume`
  - Button 3: `⏩ Done (advance)`
  - Button 4: `🐢 Slower (-3 LPM)`
  - Button 5: `🐇 Faster (+3 LPM)`
- **Telemetry Strip (Subtle Mono):**
  - Metric 1: `Graphemes: 44`
  - Metric 2: `Writing speed: 0.70 w/s`
  - Metric 3: `Fatigue factor: 0.94`
  - Metric 4: `Syntax factor: 1.20`

---

## 4. The Core Problem (`#problem`)

- **Kicker:**
  - Text: `The transcription gap`
- **Headline (H2):**
  - Text: `Why standard speech readers fail on lined paper`
- **Intro Paragraph:**
  - Text: `Audiobooks and text-to-speech synthesizers are engineered for passive listening at 150 to 220 words per minute. Human handwriting averages 20 to 35 words per minute. Attempting to copy lecture notes from a continuous reader turns study into frustration: you write three words, scramble for your phone to pause, rewind five seconds, and lose your train of thought.`
- **Side-by-Side Comparison:**
  - **Column A: Continuous speech synthesizers**
    - Point 1: `Speaks continuously at ~160 WPM without pause.`
    - Point 2: `Forces 40+ manual screen taps per notebook page.`
    - Point 3: `Ignores handwriting fatigue, leading to wrist strain.`
    - Point 4: `Glides over complex technical words too fast to spell.`
  - **Column B: Dikta handwriting pacing**
    - Point 1: `Breaks sentences into 3 to 8 word grammatical clauses.`
    - Point 2: `Calculates writing pauses based on your letter-per-minute speed.`
    - Point 3: `Gently slows tempo as fatigue accumulates during long sessions.`
    - Point 4: `Spells technical terminology syllable by syllable.`

---

## 5. The Pacing Engine (`#pacing`)

- **Kicker:**
  - Text: `The physics of handwriting`
- **Headline (H2):**
  - Text: `Calibrated to the stroke of a pen`
- **Intro Paragraph:**
  - Text: `Dikta does not use arbitrary delays. Every pause is dynamically calculated in pure Dart from character grapheme counts, punctuation weight, session duration, and real-time voice feedback.`
- **Pacing Equation Display:**
  - Formula Box:
    ```
    gap = ((n_graphemes / writing_speed) / tempo(t)) * syntax_factor * jitter - speech_duration
    ```
- **Four Architectural Pillars:**
  - **Pillar 1: Grapheme cluster complexity**
    - Headline: `Stroke-level character timing`
    - Body: `A word's length is not measured in raw bytes. Latin characters take ~0.28 seconds to write. Devanagari and Kannada conjuncts take 0.38s to 0.45s. The engine adjusts the writing window for the exact script family.`
  - **Pillar 2: Fatigue decay curve**
    - Headline: `12-minute natural energy decay`
    - Body: `Students start sessions with brisk energy and tire over time. Dikta's tempo decays along an exponential curve from 1.0 down to 0.70 (tau = 12 minutes), matching your natural writing stamina.`
  - **Pillar 3: Sawtooth breath pauses**
    - Headline: `Restorative breath intervals`
    - Body: `Fatigue is never a dead-end drop. Every 5 minutes or at major paragraph breaks, Dikta recovers 50% of the tempo drop, giving your hand a 2.5-second breath pause before beginning the next section.`
  - **Pillar 4: Adaptive feedback loop**
    - Headline: `Responsive to your voice`
    - Body: `Saying "repeat" or "slower" immediately lowers your baseline writing speed by 0.03 words/second. Uninterrupted stretches let cadence rise smoothly.`

---

## 6. The Teacher's Spelling Method (`#spelling`)

- **Kicker:**
  - Text: `Pedagogical dictation`
- **Headline (H2):**
  - Text: `How teachers dictate unfamiliar words`
- **Intro Paragraph:**
  - Text: `When an instructor introduces a technical term, they do not merely speak it once at normal speed. They pronounce the word, break it down syllable by syllable with deliberate letter spacing, and then reassemble it.`
- **Interactive Morphological Example:**
  - Target Word: `Mitochondria`
  - Step 1: `Spoken: "Mitochondria"`
  - Step 2: `Syllable one: "M · I · T · O — mito"`
  - Step 3: `Syllable two: "C · H · O · N · D · R · I · A — mitochondria"`
- **Detection Rules:**
  - Rule 1: `Automatic threshold: Triggered for all words with 10 or more letters.`
  - Rule 2: `Morpheme dictionary: Recognizes scientific prefixes like photo-, chloro-, electro-, cardio-, and neuro-.`

---

## 7. PDF Note Structure & Diagram Space (`#pdf`)

- **Kicker:**
  - Text: `Document layout intelligence`
- **Headline (H2):**
  - Text: `Extracts headings and reserves notebook space for diagrams`
- **Intro Paragraph:**
  - Text: `Handwritten revision requires structured paper. Dikta parses PDF textbooks and lecture slides, identifying hierarchy and calculating how many notebook lines you should leave blank to sketch diagrams later.`
- **Features Grid:**
  - **Feature 1: Font-size hierarchy detection**
    - Headline: `Heading recognition`
    - Body: `Text lines printed 15% larger than the page median are classified as headings. Spoken clearly as "Heading: Principles of Cellular Respiration" to let you underline and format your notes.`
  - **Feature 2: Ruled-line diagram allocation**
    - Headline: `Diagram bounding box analysis`
    - Body: `When an embedded chart or anatomical diagram is detected, Dikta measures its height relative to the page and tells you exactly how many ruled notebook lines to leave:`
    - Sub-bullets:
      - Small diagram (<=20% height): `"Leave about 4 lines of space to draw later"`
      - Medium diagram (21-40% height): `"Leave about 8 lines of space to draw later"`
      - Large diagram (>40% height): `"Leave about 14 lines of space to draw later"`

---

## 8. Trilingual Support (`#trilingual`)

- **Kicker:**
  - Text: `Multilingual scholarship`
  - Headline (H2): `English, Hindi, and Kannada with native timbre`
  - Intro: `Built for Indian university students and polyglot learners. Powered by Gnani Cloud TTS with local SQLite chunk caching so repeated phrases never incur network delay.`
- **Three Language Cards:**
  - **Card 1: Indian English (`en-IN`)**
    - Subhead: `Timbre-v3.0 Indian English`
    - Description: `Academic delivery optimized for scientific terminology, medical notes, and engineering syllabi.`
  - **Card 2: Hindi (`hi-IN`)**
    - Subhead: `Devanagari acoustic model`
    - Description: `Accurate halant conjunct rendering and natural intonation across technical and literary Hindi texts.`
  - **Card 3: Kannada (`kn-IN`)**
    - Subhead: `Dravidian acoustic model`
    - Description: `Crisp pronunciation of complex ottakshara characters, preserving natural syllabic cadence.`
- **Offline Fallback Note:**
  - Text: `Offline Kokoro-82M and sherpa-onnx voice models remain embedded in the application architecture, ready for air-gapped study environments.`

---

## 9. Hands-Free Voice Commands (`#commands`)

- **Kicker:**
  - Text: `Zero-touch control`
- **Headline (H2):**
  - Text: `Never set your pen down to press pause`
- **Intro:**
  - Text: `Dikta integrates sherpa-onnx neural keyword spotting directly on your phone. Audio is processed locally in memory and never sent to a server.`
- **Voice Commands Table:**
  - `"pause"` — Stops playback and holds the timer in place.
  - `"resume"` — Resumes speech from the current clause.
  - `"repeat"` — Replays the current phrase and slightly widens the pause.
  - `"back"` — Rewinds to the previous sentence.
  - `"next"` — Skips forward to the upcoming clause.
  - `"slower"` — Reduces writing pace by 3 letters per minute.
  - `"faster"` — Increases writing cadence for faster note-takers.

---

## 10. Download & Installation (`#download`)

- **Kicker:**
  - Text: `Direct installation`
- **Headline (H2):**
  - Text: `Download Dikta for Android`
- **Download Action Box:**
  - Primary Button: `Download Dikta APK (v1.0.0)`
    - File target: `app-debug.apk`
    - File size: `245 MB`
  - System Specs: `Android 8.0 (Oreo) or later · ARM64 & x86_64`
  - Security Guarantee: `Air-gapped voice commands · Zero third-party telemetry`
- **Installation Walkthrough (3 steps):**
  - Step 1: `Download the APK file to your Android phone.`
  - Step 2: `Open the file and allow "Install unknown apps" in Settings.`
  - Step 3: `Launch Dikta, paste your text or upload a PDF note, and begin writing.`

---

## 11. Footer

- **Brand:** `Dikta · Archival dictation for handwriting notes`
- **Columns:**
  - **Architecture:**
    - `Grapheme Pacing Engine`
    - `Pedagogical Syllable Speller`
    - `PDF Diagram Space Allocator`
    - `Gnani TTS Interface`
  - **Open Source:**
    - `Repository`
    - `MIT License`
    - `sherpa-onnx keyword spotting`
  - **Craftsmanship:**
    - `Designed with the Unslop Craft Framework (CC BY 4.0 by @heydamir)`
- **Copyright & Legal:**
  - Text: `© 2026 Dikta Project. Built with Flutter, Dart, and sherpa-onnx. Kannada voice models Meta MMS CC-BY-NC 4.0.`
