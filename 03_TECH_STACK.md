# 03 — Tech Stack

Constraints driving every choice: **iOS + Android from one codebase, cloud-first MVP (Gnani TTS) with offline fallback planned later, English + Hindi + Kannada, on-device keyword spotting, fastest path to a working MVP.**

## Stack

| Layer | Choice | Notes |
|---|---|---|
| App framework | **Flutter (Dart)** | One codebase; good native FFI & networking support |
| Primary TTS Engine (MVP) | **Gnani Cloud TTS (`GnaniTtsEngine`)** | REST API (`https://api.vachana.ai/api/v1/tts/inference`) supporting Indian English (`en-IN`), Hindi (`hi-IN`), and Kannada (`kn-IN`) via `timbre-v3.0` / `timbre-v2.5` |
| Offline TTS Fallback (Shelved) | **Kokoro-82M / sherpa-onnx** | Preserved behind `VoiceEngine` interface for future offline mode |
| Voice commands | sherpa-onnx **keyword spotting** | About 7 English keywords. Runs strictly on-device offline. Full speech recognition is not needed |
| PDF / DOCX / TXT | Text-layer extraction, DOCX unzip | No OCR for these |
| OCR (phase 5) | ML Kit for English/Hindi; PaddleOCR (ONNX) for Kannada | Check Kannada coverage before committing |
| Storage & Cache | **Local file cache & SQLite** | Synthesized audio chunks cached by (text, voice, language) to avoid repeat network calls |
| Audio | Play WAV chunks via `audioplayers` | Pacing engine controls the gaps via timers |

## Why these choices
- **Gnani Cloud TTS** provides native, production-quality voices across all three target languages (**English `en-IN`, Hindi `hi-IN`, and Kannada `kn-IN`**) without multi-hundred-megabyte on-device model downloads, licensing constraints, or slow on-device CPU inference.
- **Local Chunk Caching** ensures repeated phrases and rewind operations never re-query the network.
- **Kokoro & sherpa-onnx** remain in the repository behind the `VoiceEngine` abstraction, allowing offline fallback to be enabled in a later phase without architectural rewrites.
- **Keyword spotting** remains strictly on-device, lightweight, hands-free, and works without sending audio to the cloud.

## Architecture (keep these boundaries)

```
UI (Flutter widgets)
   |
Session controller  <--- voice commands (on-device keyword spotter)
   |
Pacing engine (pure Dart, no audio, unit-tested)
   |       outputs: next chunk text + gap duration
   |
TTS service (interface: VoiceEngine)
   |-- GnaniTtsEngine  (Active MVP: en-IN, hi-IN, kn-IN via REST + cache)
   |-- KokoroEngine    (Shelved: offline English/Hindi fallback)
   |-- PiperEngine     (Shelved: offline fast mode)
   |-- MmsEngine       (Shelved: offline Kannada fallback)
   |
Audio player (plays WAV chunks; timer-based pauses)

Importers: TextImporter, PdfImporter, DocxImporter (OcrImporter later)
Storage: Local audio cache & SQLite
```

The `VoiceEngine` interface isolates the synthesis backend, allowing transparent switching between Gnani cloud TTS and offline engines.

## Known risks
1. **Mic echo:** the keyword spotter will hear the app's own voice. Use OS echo cancellation / voice-processing mode, recommend headphones, and keep on-screen buttons as a fallback.
2. **Slow first synthesis** on weak phones. Show a "preparing" state and pre-generate ahead.
3. **App size.** Voice packs are downloaded, never bundled.
4. **Kannada licensing.** See `02_SCOPE_AND_NON_GOALS.md`.
5. **iOS builds** need a Mac with Xcode. Android-first development is fine; keep code platform-agnostic.

## License log (update whenever something is added)
| Component | License | Commercial use |
|---|---|---|
| Kokoro-82M | Apache 2.0 | Yes |
| sherpa-onnx | Check repo before shipping | Verify |
| Piper voices | Varies per voice | Verify per voice |
| Meta MMS-TTS | CC-BY-NC 4.0 | **No** |
