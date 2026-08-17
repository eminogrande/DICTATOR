# DICTATOR

A fun, local macOS dictation app for German and English. It automatically detects the primary language of each recording; switching languages inside one short recording is not reliably supported in v0.1.0.

## Use

1. Start `DICTATOR.app`; its microphone icon appears in the menu bar.
2. Grant **Microphone** and **Accessibility** when prompted. Accessibility is required for the global Fn trigger and auto-paste.
3. Put the cursor in any text field.
4. Choose **Auto-Paste On** to insert at the current cursor, or **Off** to copy only.
5. Hold **Fn/Globe** while speaking. DICTATOR shows a real white waveform, decoded/recorded time, a live decoder-position marker, and stable confirmed/provisional text. Release Fn to save the WAV and paste that live transcript. A second full-file transcription runs only if live text is empty. The menu’s **Record/Stop** button remains available as a fallback.
6. For meetings, enable **Meeting audio: microphone + Mac audio** and grant **Screen & System Audio Recording**. The permanent WAV includes both sources. The pasted transcript is the live microphone text.

If auto-paste is unavailable, the transcript remains on the clipboard. Click **Enable Accessibility…** in the menu and allow DICTATOR under **System Settings → Privacy & Security → Accessibility**.

## What is stored

Every attempt is kept permanently. Nothing is auto-deleted. Completed recordings use one flat archive with matching names:

```text
~/Library/Application Support/DictateMac/Dictations/
000001_2026-08-14_12-30_short-headline.wav
000001_2026-08-14_12-30_short-headline.txt
000001_2026-08-14_12-30_short-headline.json
```

When optional AI enhancement succeeds, the exact local Whisper result is also kept as `000001_…_short-headline.raw.txt`; the normal `.txt` contains the validated corrected transcript.

Legacy folders migrate only after verified copies exist. `graph.json` and `INDEX.md` provide a local recording index.

The model cache lives under:

```text
~/Library/Application Support/DictateMac/Models/
```

Use **Open Archive** in the menu to open saved dictations.

## DICTATOR Brain

Choose **Open Brain…** to browse recordings, transcripts, agent sessions, Hermes memories, imported documents, repositories, source files, and functions, or search them together. Search combines lexical and local multilingual embeddings, then returns deduplicated canonical sources. Add direct text, import `.txt`, `.md`, `.json`, or `.jsonl` exports, synchronize Hermes memory, or clone/update a GitHub repository. Provenance, roles, session order, timestamps, paths, branches, and commit SHAs remain attached to their sources. The canonical graph lives under `~/Library/Application Support/DictateMac/Brain/`.

Brain manages a deterministic corpus of the ten most active nonarchived, nonfork `nuri-com` repositories measured over 90 days. Opening Brain shows the saved graph immediately, then syncs Hermes memory and checks repositories in the background at most once every 24 hours. **Update Repositories** checks immediately. Only changed default-branch commits are reindexed; deleted or renamed files and functions are removed. Repository failures are isolated and never block dictation.

### Hermes Agent compatibility

DICTATOR bundles a stdio MCP server that lets Hermes query the same canonical graph without copying it into bounded `MEMORY.md`/`USER.md`. Add the server, select only `knowledge_ingest`, `knowledge_search`, and `knowledge_stats`, then start a new Hermes session:

```bash
hermes mcp add nuanced-brain \
  --command "/Applications/DICTATOR.app/Contents/Resources/Brain/node" \
  --connect-timeout 30 \
  --env "NUANCED_KNOWLEDGE_GRAPH=$HOME/Library/Application Support/DictateMac/Brain/knowledge-graph.json" \
  --args "/Applications/DICTATOR.app/Contents/Resources/Brain/dist/index.js"
hermes mcp test nuanced-brain
```

Brain answers must cite the returned source path and say when evidence is missing. Ollama embeddings are optional and fail open to lexical retrieval.

## Optional Brain-enhanced transcripts

Expand **Brain-enhanced transcript** in the menu, save an OpenRouter API key, choose a model, then enable **Correct names and spelling**. The default model is `~deepseek/deepseek-v4-flash-latest`. After the final local Whisper pass, the model may correct only obvious recognition mistakes. Every changed word requires model confidence ≥0.90 and must pass a strict local edit-distance gate. Repository links and recall remain separate from the spoken transcript. Authentication failures disable this optional path so local delivery remains fast and available.

## Privacy

- Default mode is fully local: audio and transcription stay on this Mac.
- First launch downloads `openai_whisper-large-v3_turbo` from `argmaxinc/whisperkit-coreml` on Hugging Face.
- After that download, speech recognition runs locally through WhisperKit/Core ML.
- OpenRouter enhancement is optional and off by default. When enabled, it sends the cleaned transcript and at most eight short Brain snippets; audio and the full Brain never leave the Mac.
- The OpenRouter key is stored in macOS Keychain, not UserDefaults, source code, logs, or archive metadata.
- DICTATOR has no analytics or cloud sync.

## Build

Requires macOS 14+, Apple Silicon, Xcode 16+, and Swift 6.

```bash
git clone https://github.com/eminogrande/DictateMac.git
cd DictateMac
./test.sh
./build-app.sh
open dist/DICTATOR.app
```

`build-app.sh` creates an arm64, ad-hoc-signed app at `dist/DictateMac.app`. WhisperKit is pinned exactly to `1.1.0` in `Package.swift` and `Package.resolved`.

## Runbook

- **Model failed:** verify internet access, quit/reopen, and retry the first-run download.
- **Microphone denied:** enable DictateMac under **Privacy & Security → Microphone**.
- **Mac audio unavailable:** enable DICTATOR under **Privacy & Security → Screen & System Audio Recording**, then reopen DICTATOR.
- **Copies but does not paste:** enable DictateMac under **Privacy & Security → Accessibility**.
- **No speech recognized:** open the session’s `audio.wav`; confirm it contains audible speech.
- **Reset model:** quit DictateMac, remove `~/Library/Application Support/DictateMac/Models`, then reopen.

## Current status

Version `0.9.0`: verified dictation behavior plus multilingual hybrid Brain retrieval, source-backed semantic indexes, and incremental daily/manual managed-repository updates.
