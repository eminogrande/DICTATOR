# Recording workspace and menu-bar QA

Stacked on audio-first draft #9 at `b9a2251f31802b198b1bb5a0503b9b85ffd757d6`; issue #10, draft PR #11. No merge/release before user QA.

## Installed verification

- `/Applications/DICTATOR.app`: **0.9.30 (49)**, stable `de.emin.DictateMac` identity, one running process, strict codesign verification passed. Binary SHA-256 `252d8703ef12e7d516fcbce767974a53da15f4d4f9454f3bb80b0eddd49c12cc`.
- `./test.sh`: **110 tests, 2 opt-in integration skips, 0 failures**. `/tmp/dictator-menu-brand-tests.log`. Signed build exit 0: `/tmp/dictator-menu-brand-build.log`.
- Real installed library screenshot inspected at 0.9.29: `/tmp/dictator-library-installed.png`. Resizable 1180×808 native window with compact library, actual duration/word count, selected readable transcript and player. Window supports native fullscreen; physical fullscreen interaction was not exercised.
- Real installed 0.9.30 menu bar inspected on the active display: **white DICTATOR text + red recording symbol + REC time**. Native contrast replaces app-level labelColor/contentTintColor. The idle symbol is a template SF waveform, not the old bitmap logo.
- Live screenshots show REC advancing **0:32 → 2:03** while the user's recording remained active. `/tmp/dictator-menu-contrast.png`, `/tmp/dictator-menu-live-proof.png`; exact cropped evidence `/tmp/dictator-menu-wordmark-proof.png`. No restart after the user started this recording. Inactive-display system dimming is distinct from the former forced-black bug.
- Before replacement: no recording/transcribing metadata, no child process or audio writer. The prepared audio player held a read-only `3r` WAV descriptor; that is not a recorder. Normal NSRunningApplication termination respected the app's active-work quit guard; no forced termination.
- **83 prior source files hash-identical** after replacement and after the new live recording began. No source deletion or conversion was used for this UI fix. New recording files are intentionally outside that prior-source manifest.

## Tested regressions

Legacy duration uses real WAV headers, word count is Unicode-aware, unknown values remain unknown, browsing is read-only, rename changes dedicated title metadata only. Real silent WAV preparation/seek and injected silent transport cover playback lifecycle, synchronous pre-capture stop, cancelled/failed startup unlock and same-path finalization reload. Controller tests cover denied/invalidated Fn startup leaving no stale STARTING/playback gate.

The first rename-test comparison incorrectly compared a millisecond-encoded disk Date with higher-precision memory; the test now compares actual on-disk source metadata. A new test referenced private readiness and was corrected to the public readiness-gated action. Independent static review identified stale startup phase and same-path playback reload; both fixed with regressions.

## Honest boundary

Native live menu contrast and timer progression are visually verified, not inferred from compilation. Light/dark branding configuration is unit-tested; only the actual active dark menu was visually checked. Audible playback, physical Fn delivery, audio quality/bleed, fullscreen interaction, keyboard/VoiceOver behavior and every library click flow remain unverified by automation. No permission controls changed or model installs requested. No auto-merge.
