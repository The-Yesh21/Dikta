# AGENTS.md — Read this first

You are helping build **Dictation App** (working title): a mobile app that reads a student's notes aloud, at a human, writing-friendly rhythm, so they can copy them down by hand.

## Read these, in order
1. `01_PROJECT_OVERVIEW.md` — what we are building, the main goal, the objective, and the pacing engine
2. `02_SCOPE_AND_NON_GOALS.md` — what to ignore and what to avoid
3. `03_TECH_STACK.md` — the exact technology and why

If a request seems to conflict with these files, stop and ask. Do not silently pick a side.

## Working rules
- **Work in phases.** Do one phase at a time, in the order below. Do not start the next phase until the current one runs on a real device.
- **Ask before adding a dependency**, native code, or a new permission.
- **Show the plan first** for anything touching native build files (Android Gradle, iOS Podfile, FFI bindings).
- **Never invent APIs.** For sherpa-onnx, copy the pattern from its official Flutter example and read the package docs. If you are unsure a function exists, say so.
- **No stubs presented as finished work.** If something is mocked or TODO, say so plainly.
- **Keep the pacing engine pure Dart and separate from UI**, so it can be unit-tested without audio or a device.
- **No magic numbers.** Every tunable value (see overview) lives in one config file.
- Small, reviewable changes. No sweeping rewrites.

## Build order
1. Core loop: pasted text → chunker → pacing scheduler → English TTS → playback
2. Controls: on-screen buttons + offline voice commands (keyword spotting)
3. File import: PDF, DOCX, TXT
4. Hindi and Kannada voice packs (downloadable)
5. Image OCR (only after 1-4 work)

## Definition of done for any phase
- Runs on a real Android device (iOS verified when a Mac is available)
- Works with airplane mode on
- Pacing logic has unit tests
- No crash when text is empty, very long, or contains mixed scripts
