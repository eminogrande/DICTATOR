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

## Verification

Pending implementation and real execution.
