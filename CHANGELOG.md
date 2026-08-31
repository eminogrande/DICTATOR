# Changelog

## 0.9.24 — 2026-08-31

- Live preview restored: WhisperKit streaming now runs for live transcript regardless
  of the selected full-file engine, and loads async so it never blocks recording.
- Recent transcripts list with copy buttons added to the main window.

## 0.9.23 — 2026-08-31

- File transcription no longer spawns the borderless HUD overlay (which couldn't be
  minimized). Progress + partial text + Stop live only in the main window now.

## 0.9.22 — 2026-08-31

- VAD (Silero) enabled on whisper.cpp passes: silence and music no longer produce
  hallucinated garbage segments on long recordings.

## 0.9.21 — 2026-08-31

- File transcription: live progress bar + partial transcript + Stop button. whisper.cpp
  segments stream in and update the UI (was: blank until the whole file finished).
- File picker accepts movies (mp4/mov) in addition to audio; afconvert normalizes them.
- Meeting audio: 3 capture attempts with backoff; when another app holds the
  ScreenCaptureKit session, DICTATOR keeps recording mic-only with a clear status
  instead of blocking or hanging.

## 0.9.20 — 2026-08-31

- Recording decoupled from WhisperKit: mic now records directly to WAV via AVAudioRecorder
  when the engine is whisper.cpp or Qwen3 (the default), so recording + transcription work
  even if the WhisperKit CoreML model is missing/corrupt or still downloading. WhisperKit
  streaming is now only used for live preview when explicitly selected; a broken model no
  longer blocks the app.

## 0.9.19 — 2026-08-31

- App now opens visibly: regular activation policy (Dock icon) + a window at launch
  with Record and "Transcribe Audio File…" buttons front and center (was a hidden
  menu-bar-only app).

## 0.9.18 — 2026-08-31

- Audio file upload: menu "Transcribe Audio File…" (⌘O) opens a picker, converts any
  audio (wav/mp3/m4a/flac/ogg/aiff) to 16 kHz mono WAV via afconvert, transcribes with
  the selected engine, pastes and archives the result like a normal take.

## 0.9.17 — 2026-08-20

- whisper.cpp engine (default): Whisper large-v3-turbo via whisper.cpp sidecar with Metal —
  fastest full-file pass (~3x faster than WhisperKit), exact DE/EN auto-detect.
  Sidecar + model live under ~/Library/Application Support/DictateMac/Tools/wcpp.
- Engine picker now: whisper.cpp (fastest) / WhisperKit (built-in) / Qwen3-ASR (best German).
  Parakeet TDT v3 evaluated and rejected: outputs EN/DE code-mix even in the
  official multilingual build (see docs/ASR_BENCHMARK.md).

## 0.9.16 — 2026-08-20

- Transcription engine picker in Settings: WhisperKit (fast, default) or Qwen3-ASR
  (best German accuracy, mlx-qwen3-asr sidecar venv under
  ~/Library/Application Support/DictateMac/Tools/asr). Falls back to WhisperKit
  when the sidecar is missing. Take metadata records which engine produced it.
- Live preview/HUD stays WhisperKit in both modes; the full-file pass is engine-dependent.

## 0.9.15 — 2026-08-20

- Fn+A compress mode: hold Fn+A, speak, release Fn — transcript is compressed by local
  Ollama (qwen3:4b) into a minimal numbered list in the detected language and pasted.
  Falls back to the full transcript when Ollama is unavailable. Plain Fn behavior unchanged.
- Record Meeting start reliability: ScreenCaptureKit setup is bounded by a 5s timeout with
  one retry (mic keeps recording meanwhile), a video frame sink prevents frame-log spam,
  and Fn+R presses swallowed by an in-flight start now show a status instead of doing
  nothing. Unified-log timing (subsystem de.emin.DictateMac / Meeting) records each start.

## 0.9.14 — 2026-08-20

- Menu bar icon turns red ("waveform") while transcribing in the background — visible activity after clicking Stop.
- Dropdown now lists the 5 most recent transcripts ("Copy — <headline> — <time>"); clicking one copies it. Hover shows the full text.
- Visible-HUD flow unchanged: dictate, wait, auto-insert.

### Rationale

After Stop the user needs (1) an at-a-glance signal that work is still happening, and (2) a retrieval path that doesn't require the HUD. The menu is already the retrieval surface; transcripts belong directly in it.

## 0.9.13 — 2026-08-19

- Hide button also in the "Transcribing locally, please wait…" phase: hide it, keep working; transcription runs in the background.
- Menu bar shows a green clipboard icon when the transcript is ready; click it → "Copy Last Transcript".
- New menu entry "Copy Last Transcript — <preview>" to grab the finished text after hiding the HUD.
- Auto-Paste now targets the app you are working in at delivery time, not where the take started.

### Rationale

Blocking the user for the whole transcription is unacceptable: long takes froze the workflow. Transcription already ran detached from the UI; the fix is letting the user dismiss the wait phase and retrieve the result from the menu bar — exactly like copy-from-menu in QuickTime-style workflows.

## 0.9.12 — 2026-08-19

- Recording HUD can be hidden (eye button next to Stop). Recording continues in the background; the menu bar icon stays a red stop button.
- Menu bar icon turns into a red stop icon while recording — one click stops the take (QuickTime style), no menu detour.
- Hiding applies to the current take only; the next recording shows the HUD again.

### Rationale

The floating HUD covered work during long meetings and blocked the machine visually. Stop must always be reachable in one click from the menu bar, even with the HUD hidden.

## 0.9.11 — 2026-08-19

- Native menu bar menu: Record Meeting (Fn+R), Recent Dictations, Open Brain, Settings, Quit. Clean like the reference.
- Settings moved to a proper window; the menu no longer dumps every toggle.
- Brain search (CLI + MCP) auto-ingests new dictations before searching — a fresh recording is findable seconds after Fn release without manual sync.
- Bundles the SQLite-fast Brain: in-app search now uses the ~200ms index instead of the 58s JSON scan.

### Rationale

The popover mixed controls, status, transcripts, and API keys in one endless list. The menu should be a menu. The brain felt dead because fast search skipped archive ingest and the bundled engine predated the SQLite index.

## 0.9.10 — 2026-08-17

- One font size across the HUD: 17pt monospaced for transcript, recording bar, wait phase, and timecode.

### Rationale

Sizes kept drifting between sections. One size, one font, everywhere.

## 0.9.9 — 2026-08-17

- Use the same monospaced font for transcript text, the recording bar, and the **Transcribing locally, please wait…** phase. Matches the timer/timecode font.

### Rationale

The HUD mixed three fonts. One font reads calmer and matches the waveform timecode.

## 0.9.8 — 2026-08-17

- Fn+R meeting mode shows a red **Recording — Fn+R to stop** bar and a **Stop** button at the bottom of the HUD.
- Swallow Fn+R so the letter R is not typed into the meeting app.

### Rationale

Hold-Fn and Fn+R looked the same. The latch needs its own stop affordance.

## 0.9.7 — 2026-08-17

- Press **Fn+R** to start or stop a hands-free meeting recording of microphone + Mac audio. A second **Fn+R** transcribes.
- Fn+R asks for Screen & System Audio Recording if needed and retries Mac-audio capture once if the first start fails mid-meeting.
- After stop, the HUD says **Transcribing locally, please wait…**

### Rationale

Holding Fn for a whole meeting is unusable. Device audio already existed; the missing piece was a latch that can start after a call is already running.

## 0.9.6 — 2026-08-17

- After Fn release, show **Finalizing, please wait** with a large spinner at the bottom of the HUD, below the transcript.

### Rationale

The wait state sat between waveform and text and was easy to miss. The bottom of the box is the last thing you see before paste.

## 0.9.5 — 2026-08-17

- Lock the final Whisper pass to the detected spoken language. Do not remap it to German or English.

### Rationale

Forcing DE/EN translated other languages. Detect, lock that code, transcribe. Never translate.

## 0.9.4 — 2026-08-17

- Detect German or English on the microphone and lock Whisper to that language for the final pass. Never use the translate-to-English task.
- Transcribe the microphone only. Meeting mix still goes into the saved WAV, not into the pasted text.

### Rationale

With language unlocked, Whisper often emitted English. Mixed Mac audio made that worse. The paste should stay in the spoken language.

## 0.9.3 — 2026-08-17

- Restore the full-file Whisper pass after Fn release. Live text is a preview only and is not pasted.

### Rationale

Pasting the live decoder on Fn release cut the transcript in the middle. The saved WAV pass is slower and complete.

## 0.9.1 — 2026-08-17

- Open Brain on the saved graph immediately. Repository checks and Hermes sync no longer block browsing.
- Stop rewriting the graph on search, browse, stats, and Hermes MCP search.
- Skip embedding rebuilds during repository refresh so Brain cannot hang for tens of minutes on open.
- Sync Hermes `MEMORY.md`, `USER.md`, and saved agent sessions through **Sync Hermes Memory**, and do that automatically when Brain opens.
- Show the current Brain status in the empty list instead of a blank 0-item pane.

### Rationale

The graph already contained the ten repositories. The window looked empty because open waited on embedding and dropped every browse. Hermes was configured; the files were never imported while that check ran.

## 0.9.0 — 2026-08-14

- Add local multilingual hybrid Brain retrieval with source-backed semantic indexes and canonical evidence packing.
- Remove generic lexical-overlap `RELATED` edges from the durable graph.
- Add the ten most active `nuri-com` repositories as a managed corpus with exact branch, commit, visibility, and source provenance.
- Check managed repositories at most once every 24 hours when Brain opens; update only changed commits and remove stale files/functions.
- Add an explicit **Update Repositories** control and isolate failures per repository.
- Decode fractional hybrid ranking scores in the native Brain UI.
- Strip credential-like environment variables from Swift build subprocesses so package-plugin caches cannot capture API keys.

### Rationale

The Brain now returns compact original evidence instead of a lexical graph hairball. Repository refresh stays outside dictation and preserves the last valid graph when a clone, model, or repository fails.

## 0.8.2 — 2026-08-14

- Give the waveform and timecode a fixed 88-point header that cannot overlap transcript content.
- Give the transcript its own measured viewport below the header and update panel height before replacing live text.
- Keep fitting text anchored at the top; follow the bottom only after content truly exceeds the screen-limited viewport.
- Move saving, `Finalizing, please wait`, grounded correction, and delivery phases into the fixed header instead of provisional transcript text.

### Rationale

Audio visualization, processing state, and recognized speech are separate UI regions. Status updates can no longer displace, cover, or masquerade as spoken text.

## 0.8.1 — 2026-08-14

- Remove the Recent Focus/recall card from the recording HUD and menu.
- Grow the HUD downward with measured transcript content until 36 points before the visible screen edge; scroll only after that limit.
- Include SwiftUI line spacing in AppKit height measurement so the panel no longer underestimates long text.
- Remove the redundant recent-recordings evidence pass from optional transcript correction.
- Disable optional correction after an OpenRouter 401/403 instead of repeating an unavailable network path on every dictation.

### Rationale

The recording HUD should contain only real audio, transcript, and processing state. The complete file-based Whisper pass remains canonical even when the live transcript already looks finished.

## 0.8.0 — 2026-08-14

- Add a real white live waveform from WhisperKit's microphone-energy buffers; no generated or decorative animation.
- Show a white position marker for the latest decoded audio timestamp and `decoded / recorded` duration in the HUD.
- Keep confirmed transcript text visually stable, replace only the provisional tail, and grow the HUD with content.
- Add optional Meeting audio capture: record microphone and Mac audio in parallel, align both sources, mix them into the permanent WAV, and transcribe the complete recording locally.
- Show concrete saving, final-transcription, and delivery phases after Fn release instead of appearing frozen.
- Fix Brain “All Sources” deadlocks by draining large sidecar output without bounded pipes.
- Import pasted text, documents, Hermes memories, Hermes/agent session exports, and repositories with provenance and conversation lineage.
- Add the Hermes `MemoryProvider` adapter while keeping `MEMORY.md` and `USER.md` as the curated always-on layer.
- Require every changed transcript term to occur in Brain evidence; phonetically retrieved `passkey` evidence can ground `PASCII → passkey`, but no hard-coded replacement exists.
- Preserve repository source contents when function relationships are merged into the graph.

### Rationale

The waveform and marker expose real recording and decoder progress without adding explanatory frontend copy. Nuanced remains the canonical local graph; Hermes compatibility is additive rather than a second competing memory database.

## 0.7.0 — 2026-08-14

- Replace the recording waveform with real WhisperKit streaming transcription.
- Render confirmed text at 22 px and provisional text at 22 px in a lighter color; provisional words may change as Whisper decodes.
- Show an LLM-generated recent-work recall card until the first spoken words arrive.
- Enforce a 17 px minimum across the menu, Brain browser, source metadata, and graph labels; remove caption-sized copy.
- Restrict OpenRouter to high-confidence speech-recognition corrections: changed words require confidence ≥0.90 and a strict local edit-distance gate.
- Keep recall, repository links, and suggested context separate; only corrected spoken text is copied or inserted.
- Save the same audio samples used by live Whisper as the permanent WAV before the final local transcription pass.

## 0.6.0 — 2026-08-14

- Replace fake dots/previous-transcript animation with a sweeping waveform sampled from the actual WAV and a recent-work summary from Brain.
- Add optional Keychain-backed OpenRouter enhancement for names, spelling, punctuation, and grounded supporting context.
- Send only the cleaned transcript plus up to eight bounded Brain snippets; never send audio or the full graph.
- Preserve exact local Whisper output as `.raw.txt` whenever an enhanced `.txt` is accepted.
- Reject model output that rewrites too much of the spoken text and fall back to the untouched local transcript.

## 0.5.2 — 2026-08-14

- Replace the unreliable SwiftUI `MenuBarExtra(.window)` shell with a native `NSStatusItem` and `NSPopover`.
- Keep the same compact SwiftUI menu content and open the Brain through a native retained window.
- Log real status-button clicks and resulting popover visibility for installed-app verification.

## 0.5.1 — 2026-08-14

- Fix the menu-bar icon opening no popover after the transcription HUD was added.
- Create the non-activating HUD panel lazily on first transcription instead of during SwiftUI scene initialization.

## 0.5.0 — 2026-08-14

- Add a real Brain browser with Home, All Sources, Recordings, Transcripts, Repositories, Files, and Functions.
- Add persistent Home/Back/Clear navigation, recent recordings, source details, explicit Open Source actions, and connected-evidence graphs.
- Add type-filtered sidecar browsing with deterministic recent-first recording order.
- Connect the canonical DICTATOR graph to Hermes through three bounded MCP tools: ingest, search, and stats.
- Keep retrieval source-cited and fail closed when evidence is absent; multilingual semantic retrieval remains the next quality upgrade.

## 0.4.1 — 2026-08-14

- Keep local transcription visibly alive with a non-activating floating HUD above the current app.
- Show immediate dots, then character-by-character type/delete activity sourced only from the previous real transcript.
- Keep keyboard focus in the original target app and hide the HUD on completion or failure.

## 0.4.0 — 2026-08-14

- Integrate Nuanced Brain directly into DICTATOR with native search, GitHub import, graph statistics, source links, and visualization.
- Bundle Node and the Nuanced engine inside the signed app; no separate MCP installation is required for the UI.
- Store recordings as matching flat WAV/TXT/JSON sets with sequence, local timestamp, headline, summary, and keywords.
- Migrate legacy folders by copy, byte verification, metadata rewrite, then removal; decode historical `delivery: copied` safely.
- Animate local transcription with dots and type/delete frames sourced only from the previous real transcript.
- Keep numeric preferences such as `16` searchable and replace stale archive graph nodes on refresh.

## 0.3.1 — 2026-08-13

### Fixed

- Use a real Cmd-V key sequence as the primary Auto-Paste path for Electron and web editors.
- Stop treating a successful Accessibility attribute call as proof that the target editor changed.
- Retain direct Accessibility insertion as a fallback when target activation or key-event creation fails.

## 0.3.0 — 2026-08-13

### Added

- Persistent **Auto-Paste** On/Off switch; defaults to On.
- Clipboard-only delivery mode when Auto-Paste is Off.
- Per-session metadata recording the chosen Auto-Paste state and exact delivery result.
- Archive-completeness regression test covering audio, transcript, and metadata.

### Verified

- Existing archive audit: 28/28 session folders contain `audio.wav`, `transcript.txt`, and `metadata.json`.
- Completed sessions contain non-empty transcripts; no historical files were removed during installation.

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
