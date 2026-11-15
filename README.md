# Dikta — Solution Pitch

> **Notes read aloud at the rhythm of handwriting.**  
> A mobile handwriting dictation companion for students copying study notes by hand.

---

## 1. The Problem
Students retain up to **40% more conceptual information** when copying notes by hand, but transcribing from screens or textbooks causes constant visual context-switching, neck fatigue, and fragmented focus.

Existing audiobooks and Text-to-Speech (TTS) tools read continuously at **130–170 words per minute**. Because human handwriting speed averages only **25–40 WPM**, students are forced to pause and rewind every three seconds. Audio tools built for *listening* fail completely for *writing*.

---

## 2. The Solution: Dikta
**Dikta** is an intelligent mobile companion that dictates study material in short, digestible phrases (3–8 words), paired with mathematical writing pauses dynamically matched to the student's physical handwriting cadence.

```
[Phrase Spoken at 0.80x] ──> [Teacher Syllable Breakdown] ──> [Calibrated Writing Pause] ──> [Next Phrase]
```

---

## 3. Core Differentiators

### A. Grapheme-Calibrated Pacing Engine
Writing time is calculated using Unicode grapheme clusters (Dart `characters` package), not arbitrary word counts:
$$\text{Writing Budget} = \frac{\text{Graphemes}}{\text{User LPM}} \times 60 \times \text{Script Factor}$$
$$\text{Pause Gap} = \max(\text{Min Gap}, \text{Writing Budget} - 0.5 \times \text{Speech Duration}) + \text{Boundary Pause}$$
- **Fatigue Decay**: Naturally decelerates rhythm over a 12-minute study block ($e^{-t / \tau}$) to account for muscle exhaustion.
- **Sawtooth Recovery**: Injects natural breathing pauses at paragraph transitions.
- **Adaptive Feedback Loop**: Automatically tightens or relaxes pacing when the student taps *Done* early or commands *Slower*.

### B. Pedagogical Syllable Spelling
For technical words ($\ge 10$ letters), Dikta abandons robotic letter-dumping and speaks like an educator:
> *"M, I, T, O · mito · C, H, O, N, D, R, I, A · mitochondria."*

### C. Structural PDF Note Parsing & Diagram Space Allocation
- **Heading Detection**: Statistically identifies headings by font size ($\ge 1.15\times$ body text) and announces: *"Heading: [Title]"*.
- **Diagram Space Calculation**: Analyzes image bounding boxes relative to page height and instructs students:
  - Small ($\le 20\%$): *"Leave ~4 lines of space to draw later."*
  - Medium ($21\% - 40\%$): *"Leave ~8 lines of space to draw later."*
  - Large ($> 40\%$): *"Leave ~14 lines of space to draw later."*

### D. Trilingual Indian Language Support
Cloud-first integration via **Gnani Vachana AI** supporting native accents and phonetic nuance:
- **English (`en-IN`)**: *Shivani* (`timbre-v3.0`)
- **Hindi (`hi-IN`)**: *Nalini* / *Shivani* (`timbre-v2.5` / `v3.0`)
- **Kannada (`kn-IN`)**: *Saanvi* / *Kavin* (`timbre-v2.5`) with UTF-8 non-Latin byte serialization.

---

## 4. Architecture & Tech Stack

| Layer | Technology | Key Responsibility |
|---|---|---|
| **Framework** | Flutter 3.x / Dart | Cross-platform UI & pure Dart pacing engine |
| **Pacing Core** | Pure Dart | Grapheme timing, fatigue curves, zero UI/audio coupling |
| **TTS Engine** | Gnani Cloud API + Cache | 600ms leading zero-PCM silence to prevent DAC clipping |
| **Document Parser** | `syncfusion_flutter_pdf` | Pure Dart PDF text line bounds & image ratio analysis |
| **Audio Playback** | `audioplayers` | Low-latency audio streaming & pre-roll synchronization |
| **Web Landing** | Semantic HTML5 / CSS / JS | Unslop craft design, fluid ink waves, APK distribution |

---

## 5. Quick Start & Installation

### Android APK Direct Download
- Download the standalone APK from the landing page or [GitHub Release `v0.2.0-alpha`](https://github.com/The-Yesh21/Dikta/releases/tag/v0.2.0-alpha).
- Install on any Android 8.0+ device (`adb install -r app-debug.apk`).

### Local Development
```bash
# Clone repository
git clone https://github.com/The-Yesh21/Dikta.git
cd Dikta

# Run pure Dart unit & widget tests (117 tests)
flutter test

# Build debug APK
flutter build apk --debug

# Run web landing page locally
python -m http.server 8080 --directory web
```

---

## 6. Live Links
- **GitHub Repository**: [github.com/The-Yesh21/Dikta](https://github.com/The-Yesh21/Dikta)
- **Latest Release (`v0.2.0-alpha`)**: [github.com/The-Yesh21/Dikta/releases/tag/v0.2.0-alpha](https://github.com/The-Yesh21/Dikta/releases/tag/v0.2.0-alpha)
- **Web Landing Page**: Hosted on Vercel with direct APK download redirect.
