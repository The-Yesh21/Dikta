# 02 — Scope: What to Ignore and What to Avoid

## What to IGNORE (out of scope for the MVP)
Do not build, plan for, or add placeholders for any of these unless explicitly asked:

- **Backend, servers, user accounts, login, cloud sync.** Everything is local; no custom server infrastructure or user accounts.
- **Cloud speech recognition.** Voice commands remain strictly on-device keyword spotting. (TTS is cloud-first MVP via Gnani, with offline TTS as a later fallback).
- **Voice cloning** or custom user voices.
- **Handwriting recognition or checking** what the user wrote.
- **Note-taking, editing or formatting features.** The app reads text; it is not a notes app.
- **AI summarising, rewriting or translating** the text.
- **Languages beyond English, Hindi and Kannada.**
- **Payments, subscriptions, ads, analytics, telemetry.**
- **Social features:** sharing, collaboration, leaderboards.
- **Web, desktop and tablet-specific layouts.** Phones only.
- **Image OCR**, until phases 1-4 work (see `AGENTS.md` build order).
- **Fancy visual design.** Clean and usable is enough for the MVP.

## What to AVOID (how we build)

### Technical
- Do **not** call unapproved network APIs at runtime. Permitted network use: Gnani cloud TTS API for the MVP (`https://api.vachana.ai/api/v1/tts/inference`), and downloading offline voice packs when enabled.
- Do **not** bundle voice models inside the app binary. Download on demand.
- Do **not** put pacing logic inside UI widgets. Keep it pure Dart and testable.
- Do **not** hardcode tunable numbers. Use the config file.
- Do **not** run heavy model inference on the UI thread. Use isolates or native background threads.
- Do **not** add a dependency, plugin or permission without asking first.
- Do **not** guess sherpa-onnx APIs or model file formats. Follow the official examples.
- Do **not** assume emulators prove anything about audio or inference. Test on a real phone.

### Process
- Do **not** build several phases at once.
- Do **not** rewrite working code for style reasons.
- Do **not** mark something done that is mocked, stubbed or untested.
- Do **not** silently change the tech stack. Propose, then wait.

### Licensing
- The Kannada voice (Meta MMS-TTS) is **non-commercial only (CC-BY-NC)**. It is allowed for the prototype and demos. Keep it isolated behind a voice-engine interface so it can be swapped before any commercial release.
- Record the license of every model and library added, in `03_TECH_STACK.md`.

### Product
- Do **not** add features "because users might want them". If it does not serve the main goal in `01_PROJECT_OVERVIEW.md`, leave it out.
- Do **not** make the pacing perfectly regular. Randomness and natural pauses are the point.
