# Minimal DICTATOR menu QA

## Why

The native dropdown duplicated the application: oversized transcript/status panel, nested recent-session menus, duplicate navigation and technical destinations. The menu now acts as a quick remote control; the library remains the complete recording workspace.

Continuation of issue #10 and draft PR #11 on verified base `1aa5e535005d18df18128d2e4d16db81c177297d`. No merge or release approval.

## Behavior

- Five idle actions: Aufnahme starten, Datei importieren, Aufnahmen öffnen, Einstellungen, Beenden. Explicit start/stop and cancellation remain controller-gated. No nested menus or transcript dump.
- Header is 56pt idle / 100pt recording. Real source levels, neutral waiting state and elapsed time remain visible during recording. Full source errors remain in tooltips/accessibility labels and the library.
- Preferences really opens the preferences sheet. Full library functionality remains reachable: playback, rename, transcript reading, copy, export, Finder reveal, errors and retry. Archive folder and knowledge archive remain in preferences through explicit callbacks.
- Fn guidance appears only when the actual final engine can dictate. AppKit rejects the Fn key-equivalent modifier, so the misleading menu shortcut was removed; the real global Fn monitor is unchanged.

## Executed verification

- Reviewed final source: `./test.sh` passed, 113 tests, 3 explicit opt-in skips, 0 failures. Log `/tmp/dictator-minimal-menu-tests-reviewed.log`.
- Reviewed release build: `/tmp/DICTATOR-minimal-0.9.31.app`, version 0.9.31 build 50. Build exit 0, stable `de.emin.DictateMac` designated requirement. Log `/tmp/dictator-minimal-menu-build-reviewed.log`.
- Opt-in native visual test passed: actual NSMenu popup captured in light and dark appearance at 280 x 199pt. Final UI screenshots `/tmp/dictator-minimal-menu-final-qa/menu-light.png` and `/tmp/dictator-minimal-menu-final-qa/menu-dark.png`. Inspected both, including final aligned quit icon. No clipped labels or obsolete panel/submenus. The later review change only adds a neutral translation for the controller's Listening state.
- Native menu actions dispatched to distinct library/preferences callbacks. Tests cover five visible actions, no submenus, controller availability, Fn shortcut representation, shrinking status, real-view bounds and source-state classification.
- Independent bounded review `/tmp/dictator-minimal-menu-review.md` found one remaining Listening-state classification defect. Fixed with explicit `Wartet auf Ton` mapping and a regression assertion; reviewed test/build both passed afterward. No controller, archive, capture or playback implementation changed.
- Existing 83-file source manifest remained hash-identical while the user's session `000034_2026-09-07_15-04_recording` continued. The idle installer guard was executed read-only and detected both recording metadata and the live writable audio descriptor.

## Installation boundary

The native screenshots are isolated real UI tests, not screenshots of a newly installed recorder. The installed app was still 0.9.30 build 49 and actively recording when QA finished. Do not interrupt it. The prepared idle-only installer pins both binary hashes, waits for capture/processing to end, requests normal termination with the app's own guard, and checks installed bytes/version/signature, a surviving single PID and original-file hashes. Installation state is recorded separately in `/tmp/dictator-minimal-install-status.json`.

Full physical Fn delivery, live recording audio quality, actual library-to-preferences sheet focus and installed menu interaction are not newly proven by these menu tests. No permission controls, user recordings or model downloads were changed.
