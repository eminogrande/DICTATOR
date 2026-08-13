# Changelog

## 0.2.0 — 2026-08-13

### Fixed

- Preserve the same macOS Accessibility identity across local rebuilds with a stable designated signing requirement.
- Keep direct focused-field insertion and verified Cmd-V fallback.

### Changed

- Rename the visible app to **DICTATOR** while preserving the bundle ID and existing archive.
- Add a stern microphone with peaked cap and moustache as the app and menu-bar icon.

## 0.1.2 — 2026-08-13

### Fixed

- Insert the transcript directly into the focused text field through macOS Accessibility.
- Wait for target-app activation before using Cmd-V as a compatibility fallback.
- Keep the transcript on the clipboard when neither insertion route succeeds.

## 0.1.1 — 2026-08-13

### Added

- Global hold-Fn/Globe push-to-talk: press to record, release to transcribe and paste.
- Menu text and permission guidance for the Fn workflow.
- Modifier-state regression tests, including duplicate-event suppression.

### Kept

- The visible menu Record/Stop button remains the no-hotkey fallback.

## 0.1.0 — 2026-08-13

### Added

- Native macOS menu-bar recording UI.
- Local German/English transcription with WhisperKit `large-v3-turbo`.
- Permanent per-dictation WAV, transcript, and JSON metadata archive.
- Automatic paste into the previously active application through Accessibility.
- Clipboard fallback when Accessibility or the target application is unavailable.
- Microphone/Accessibility permission guidance and archive shortcut.
- Deterministic archive/metadata/transcript-cleanup tests.
- Reproducible ad-hoc-signed `.app` build script.

### Rationale

The first version deliberately uses one visible Record/Stop control and one pinned local model. It avoids accounts, cloud storage, global shortcuts, model selection, and editing so the core dictation path stays understandable and testable.
