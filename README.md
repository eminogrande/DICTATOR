# DICTATOR

A fun, local macOS dictation app for German and English. It automatically detects the primary language of each recording; switching languages inside one short recording is not reliably supported in v0.1.0.

## Use

1. Start `DICTATOR.app`; a waveform appears in the menu bar.
2. Grant **Microphone** and **Accessibility** when prompted. Accessibility is required for the global Fn trigger and auto-paste.
3. Put the cursor in any text field.
4. Choose **Auto-Paste On** to insert at the current cursor, or **Off** to copy only.
5. Hold **Fn/Globe** while speaking; release it to transcribe. The menu’s **Record/Stop** button remains available as a fallback.

If auto-paste is unavailable, the transcript remains on the clipboard. Click **Enable Accessibility…** in the menu and allow DICTATOR under **System Settings → Privacy & Security → Accessibility**.

## What is stored

Every attempt is kept permanently. Nothing is auto-deleted. Each session gets its own folder:

```text
~/Library/Application Support/DictateMac/Dictations/<UTC timestamp>/
├── audio.wav
├── transcript.txt
└── metadata.json
```

The model cache lives under:

```text
~/Library/Application Support/DictateMac/Models/
```

Use **Open Archive** in the menu to open saved dictations.

## Privacy

- Audio and transcription stay on this Mac.
- First launch downloads `openai_whisper-large-v3_turbo` from `argmaxinc/whisperkit-coreml` on Hugging Face.
- After that download, speech recognition runs locally through WhisperKit/Core ML.
- DictateMac has no account, analytics, cloud sync, or upload code.

## Build

Requires macOS 14+, Apple Silicon, Xcode 16+, and Swift 6.

```bash
git clone https://github.com/eminogrande/DictateMac.git
cd DictateMac
swift test
./build-app.sh
open dist/DICTATOR.app
```

`build-app.sh` creates an arm64, ad-hoc-signed app at `dist/DictateMac.app`. WhisperKit is pinned exactly to `1.1.0` in `Package.swift` and `Package.resolved`.

## Runbook

- **Model failed:** verify internet access, quit/reopen, and retry the first-run download.
- **Microphone denied:** enable DictateMac under **Privacy & Security → Microphone**.
- **Copies but does not paste:** enable DictateMac under **Privacy & Security → Accessibility**.
- **No speech recognized:** open the session’s `audio.wav`; confirm it contains audible speech.
- **Reset model:** quit DictateMac, remove `~/Library/Application Support/DictateMac/Models`, then reopen.

## Current status

Version `0.3.1`: persistent Auto-Paste On/Off, clipboard copy in both modes, permanent audio/transcript/metadata history, hold-Fn push-to-talk, and local German/English transcription.
