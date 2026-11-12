# 01 — Project Overview

## What we are building
A mobile app (iOS + Android, one codebase) that **dictates notes aloud so a person can write them down by hand**.

The user flow:
1. Open the app
2. Import text: paste, or upload a PDF, Word file, or image (images come in a later phase)
3. Pick a **voice** and a **dictation speed**
4. Listen. The app speaks the text in short phrases with human-like pauses so the listener can write each phrase
5. Control it by **voice commands** (pause, resume, repeat, slower, etc.) or on-screen buttons

It is **cloud-first for the MVP (using Gnani TTS)** with **offline fallback planned for later**, in **English, Hindi and Kannada**. Voice commands remain **strictly on-device keyword spotting**.

## Main goal (one sentence)
> A student can import notes and hear them dictated at a natural, writer-friendly rhythm, hands-free, in English, Hindi or Kannada (cloud-first MVP via Gnani, offline fallback later; voice commands on-device).

Every decision should be checked against this sentence.

## Objective
Ship a working MVP that proves people would actually use this to copy notes. Success for the MVP means:
- A 2-page document can be dictated start to finish via Gnani cloud TTS (with chunk caching), with no audible stalls between phrases (the next phrase is always ready before the pause ends)
- Voice commands reliably pause and resume playback, even with the app's own voice playing (on-device keyword spotting)
- The pacing feels human, not robotic, when tested by real students
- Future offline voice packs download on demand, so the install stays small

## What makes this different from a normal text-to-speech reader
Normal readers read continuously. This app is built for **writing**:
- Phrase chunking (about 3-8 words at a time), then a pause long enough to write them
- Pace defined by the **writer's speed**, not just voice speed
- A dictator that behaves like a human: starts with energy, slows gradually, takes breaths, never sounds metronomic
- Dictation-specific commands: repeat, back, slower

## The pacing engine (core differentiator)

All values below are **starting defaults**, tunable by ear. They live in one config file.

```
t        = minutes elapsed in this session
tempo(t) = tempo_min + (tempo_0 - tempo_min) * e^(-t / tau)

gap = ( n_words / writing_speed ) / tempo(t)
      * syntax_factor
      * jitter
      - speech_duration_of_chunk          (never below min_gap)
```

| Parameter | Default | Meaning |
|---|---|---|
| `tempo_0` | 1.0 | Energy at the start |
| `tempo_min` | 0.7 | Floor the tempo decays toward |
| `tau` | 12 min | How fast energy fades |
| `writing_speed` | 0.4 words/sec | The user's handwriting speed; adapts during the session |
| `syntax_factor` | comma 1.2, sentence end 1.8, paragraph 2.5 | Longer pause at natural boundaries |
| `jitter` | lognormal, sigma about 0.15 | Randomness so rhythm is never mechanical |
| `min_gap` | 0.3 sec | Shortest allowed pause |
| `fatigue_strength` | 1.0 (slider 0-1) | Scales how much tempo decays; 0 turns it off |

Extra behaviours:
- **Sawtooth, not a pure decay:** partially restore tempo at paragraph breaks or about every 5 minutes (a "breath")
- **Per-chunk voice variation:** about plus or minus 5% speed, slightly slower delivery at sentence ends
- **Adaptive:** each "repeat" or "slower" command lowers `writing_speed` a little; a long stretch with no commands can raise it slightly

## Voice commands (v1 set)
`pause`, `resume`, `repeat`, `back`, `next`, `slower`, `faster`.
Always have an on-screen button for each as a fallback.

## Languages
- English, Hindi, Kannada for dictation
- Voice commands use a small set of English keywords in all modes
