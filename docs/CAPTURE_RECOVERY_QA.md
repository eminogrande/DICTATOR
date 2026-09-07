# Capture recovery QA — 0.9.32 / build 51

## Verified artifact

`/tmp/DICTATOR-capture-0.9.32.app` passed the release build and deep/strict signature verification. Bundle identity remains `de.emin.DictateMac`; designated requirement is unchanged. Installed app was still 0.9.30 / 49 during verification. No active app was restarted.

## Executed checks

Swift: **129 executed, 126 passed, 3 explicitly skipped, 0 failures**. Includes 8 capture-health and 8 PCM-recovery tests, 13 playback tests and 10 whisper.cpp task tests. Brain: **28 passed, 0 failures**; MCP self-check command completed successfully.

Logs: `/tmp/dictator-capture-recovery-tests-reviewed.log`, `/tmp/dictator-capture-recovery-build.log`, `/tmp/dictator-capture-brain-tests.log`.

The first-mix regression retains two seconds of native-layout PCM behind a stale one-second header and adds a valid one-second system track. It verifies the full two-second mixed output, nonzero second-half signal, original microphone/system bytes, warning retention, library selection and idempotent preparation. A separately generated real AVAudioFile verifies finalized native PCM16 passes through unchanged. These are file/lifecycle tests, not physical capture proof.

## Independent review

The first reviewer found an initial-Stop ordering bug: mixing could occur before microphone recovery. Stop and Retry now share `prepareSavedAudio(for:)`; the duplicated earlier mixing blocks were removed. The final independent review found no remaining introduced blocker. Full reports: `/tmp/dictator-capture-recovery-review.md` and `/tmp/dictator-capture-recovery-review-final.md`.

## Six historical findings, exact disposition

Duplicate-instance termination already bypassed lazy archive/controller startup. Fn+R startup already retained the meeting transition; this follow-up also clears its intent after failure, with a regression. Quick Fn capture is now mic-only, so its old system-track conversion branch no longer owns a system track. Known native microphone header recovery is newly implemented as copy-only salvage. Capture receipt now follows successful storage; unexpected microphone cessation ends REC and preserves warnings through completed transcription.

The remaining finding is **partially addressed, not closed across all engines**: default Fast/whisper.cpp can stop its background ASR before starting the next meeting; Qwen/Built-in remain serialized. This change does not implement concurrent capture/ASR or all-engine cancellation.

## Data and installation boundary

The earlier manifest contained 83 files, including derived `INDEX.md`. All **82 protected source audio/text/metadata files remained unchanged**, none missing. Only derived `INDEX.md` changed; `ArchiveStore.rebuildGraph()` regenerates it. Evidence: `/tmp/dictator-capture-source-verification.json`.

The old 0.9.31 installer was paused without stopping the recording. Replacement installation must wait for both capture and processing to finish, verify pinned binaries, honor normal app termination refusal, preserve all sources and read back the exact installed app. No merge or release before user QA.

Skipped opt-in checks: native menu rendering, actual installed-sidecar inference, and explicit saved-user-session retry. Physical Fn/capture/device-disconnect/newly-installed-app QA remains unperformed while the user's recording is active. Recovery deliberately rejects unsupported/ambiguous WAV layouts and never repairs an original in place.
