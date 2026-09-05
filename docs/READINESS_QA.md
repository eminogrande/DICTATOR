# Selected-engine readiness and Fn HUD (#6)

Base: `0a4bae7941bd5baabf1240d3846f136d8b899b8c` (`origin/main`).
No overlapping open PRs or repository rulesets/AGENTS files found at intake.

## Acceptance

- Startup shows loading, then ready only after real local inference succeeds, or an actionable error.
- Selected final engine gates Record / Fn / Fn+R / Fn+A and file transcription. Optional preview does not gate sidecars.
- Missing models, VAD, runtime dependencies and stale selection results cannot enable recording.
- Hold-Fn shows live transcript when available, otherwise explicit recording/loading status, never an empty HUD.
- Existing archives and background file transcription remain intact.
- Tests and signed build must pass; inspect live jobs before installation/restart, never interrupt active work.
- Draft PR stays unmerged pending user QA. Build alone is not hotkey/transcription proof.

## Verification — 2026-09-05

- `./test.sh`: **exit 0**, 68 tests, 1 opt-in integration skipped, 0 failures. Final source (including app-resource lookup) log: `/tmp/dictator-readiness-tests-packaged.log`.
- `DICTATOR_VALIDATE_LOCAL_ENGINES=1 DICTATOR_VALIDATE_ENGINE=whisperCpp ./test.sh --filter testInstalledSidecars`: **exit 0**, actual local speech inference through whisper.cpp + Silero VAD. `/tmp/dictator-readiness-fast-final.log`.
- Both-sidecar integration attempt: **exit 1**, Fast succeeded; Best quality failed because `Qwen/Qwen3-ASR-0.6B` has no offline cached snapshot. Exact diagnostics: `/tmp/dictator-readiness-inference.log`. This engine must remain unavailable, not silently fall back or download. Built-in real inference has not been separately proven.
- Controller tests exercise loading/error Fn gating, missing model installation, a real missing-runtime subprocess failure, retry, stale selection rejection, and switching away from suspended Built-in validation. No production model/dependency files were removed for tests.
- Optional preview never sets final-sidecar readiness. Preview-start errors now fall back to WAV. Visible HUD presentation always has a nonempty status, with existing wait copy preserved.
- Bundled Brain `npm test`: **exit 0**, 28/28 pass. `/tmp/dictator-readiness-brain-tests.log`.
- `DICTATOR_BUILD_APP=/tmp/DICTATOR-readiness-0.9.27.app ./build-app.sh`: **exit 0**, release binary, Brain build and strict signature verification pass. `/tmp/dictator-readiness-build-packaged.log`. Earlier build attempt failed because source changed during compilation; final rerun succeeded.
- Resource lookup explicitly checks `Contents/Resources/DictateMac_DictateMac.bundle`, avoiding SwiftPM's development-path fallback in the installed app.
- Before replacing the app: no recording/transcribing metadata, no child processes, no open archive files; old UI displayed Record, not Stop. Only idle old PID 70589 was terminated. No active job was interrupted.
- Installed `/Applications/DICTATOR.app`, version **0.9.27 (46)**, bundle ID **de.emin.DictateMac**, executable **DictateMac**, designated requirement unchanged (`identifier "de.emin.DictateMac"`). One installed process observed, PID **18115**. Strict signature verification exit 0.
- Installed UI screenshot shows **Ready — hold Fn to talk**, Record/File buttons, minimal collapsed Advanced and existing transcript list: `/Users/eminmahrt/.hermes/cache/images/computer_use_9c35aa85aa52490dae9c94c34a53075c.png`.
- All **36 source archive files** (audio/transcript/session metadata) hash-identical across install. Only derived `Dictations/graph.json` regenerated during the existing `ArchiveStore.init → rebuildGraph` startup path. Hash manifest: `/tmp/dictator-readiness-archive-before.json`.
- Installed executable SHA-256: `4c7d45b9e9826ca32c9e502ac996fc71bfe54cb907d71b034fbe0f36175d4e9d`.

## Remaining QA / limitations

- **No claim of physical Fn → microphone → live text → cursor insertion proof.** Controller/HUD regression tests and installed Ready UI are verified, not that end-to-end interaction. GUI element input encountered cua-driver snapshot/coordinate problems; permission UI was not touched.
- Built-in inference and live preview still need actual runtime QA; Best quality needs its locally installed weights before it can become ready.
- Existing Swift 6-mode concurrency warnings in subprocess waits / file-task locks remain warnings under the repository's current language mode.
- Draft PR #7 stays unmerged, issue #6 remains open pending user QA. No release created.
