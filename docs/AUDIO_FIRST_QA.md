# Audio-first meetings and visible sessions (#8)

Draft PR #9 is stacked on readiness draft #7 at `1b98ab77cb45e2eb0ea10ecefea7a1db73527f2a`. No merge or release before user QA.

## Shipped behavior

- Meeting Record/Fn+R uses mic-to-disk independently of transcription readiness and preview. Mac audio has a separate incremental PCM WAV with real source levels and bounded startup/stop. Mixing writes a separate derived WAV; source tracks are not replaced.
- Quick Fn/Fn+A remains readiness-gated, microphone-only, live preview if available, final full-pass delivery. A short chord delay distinguishes Fn+R; cancelling a suspended meeting start prevents late recording.
- Persistent colored menu-bar REC/TXT elapsed counters, source meters and sticky Saved/Done/Failed. Native dropdown uses common-mode timers and does not stop on icon click. Model/Fn readiness stays visible in the main window.
- All archive sessions, not only successes, appear with dates/states, Transcribe/Retry, Show audio and completed Copy/Open. Retry retains session identity/source audio and backs up any previous nonempty text before replacement. Derived graph failure cannot downgrade a completed source transcript.
- Background meeting/import/retry never auto-pastes. Cancelling ASR retains a saved session. New meeting requests preempt cancellable ASR. Closing windows keeps work alive; Quit refuses to silently abandon active work. Non-cancellable Built-in/Qwen transcription must finish before another recording; multi-job concurrency is not implemented.

## Verified execution

- `./test.sh`: exit 0; **88 tests, 2 opt-in integration skips, 0 failures**. `/tmp/dictator-audio-first-tests-shipped.log`.
- Brain `npm test`: exit 0; **28 tests, 28 pass, 0 failures**. `/tmp/dictator-audio-first-brain-tests.log`.
- Explicit installed whisper.cpp readiness speech/VAD inference: exit 0. `/tmp/dictator-audio-first-inference.log`.
- The retained failed long meeting was retried through the actual controller + WhisperCppFileTask pipeline, not synthetic ASR. `testExplicitSavedSessionRetry` exit 0. Duration **3013.007625 seconds**, source WAV **96420340 bytes**, final TXT **37847 bytes**, same session ID `000031_2026-09-07_11-25_recording`, status completed. No auto-paste.
- Long meeting SHA-256 unchanged before/after retry: `22a4ce658d2da11082c881676caaca8b8115ec38e09987d97a5f7a8fa4a569f1`. Transcript contents remain local and are not included in this public QA document. Retry log: `/tmp/dictator-long-meeting-retry.log`.
- Failure reproduction: running the installed whisper-cli without its DYLD library path aborts with signal 6 before inference because `@rpath/libwhisper.1.dylib` resolves only to a deleted `/tmp/whisper.cpp/build/bin`. Branch's shared local environment resolves installed sibling dylibs; actual short retained audio transcribed successfully. Existing WAV/VAD/-p4 was not the cause established by the experiment. Historical errors lacked stderr, so exact historical causality beyond this matching reproduction cannot be proved.
- Signed release build exit 0: `/tmp/dictator-audio-first-build-shipped.log`. Installed `/Applications/DICTATOR.app` **0.9.28 (47)**, stable bundle ID/executable/designated requirement, exactly one process. Final installed executable SHA-256: `9cc4a7e74a06259e042625ffc26e144c1217e70758a908db393975f3823eef45`.
- Old `dist` app was **0.9.26**, despite `/Applications` having previously been upgraded. The stale app finished its active take before installation; no recorder/job was killed. Old dist copy removed after new installed launch was verified.
- Final installation source manifest: **82 source files**, all hash-identical across final replacement. Earlier first launch intentionally recovered one stale recording metadata state; all **26 existing WAVs** were unchanged. Derived graph/index excluded from source hashes.
- Archive readback: **28 sessions: 17 completed, 9 failed, 2 saved**. Older failures remain intentionally visible and retryable.
- Installed screenshot `/tmp/dictator-audio-first-shipped.png` captures the final app. Earlier inspected snapshots established visible saved/failed rows with audio/retry actions and Ready for Fn. Readiness-transient text is no longer treated as a saved-session error; retry waits for model readiness while Record remains independent.

## Hardware/UI QA boundary

Desktop automation's Accessibility check returned false; cua-driver could not resolve actionable windows. Permission controls were not touched. **No claim of verified physical Fn input, live microphone/Mac capture, live meter motion, open-menu timer ticks, or cursor insertion on the installed build.** Source code, isolated PCM/mix/cancellation tests, real saved-audio ASR, installed UI visibility and signature are verified. User permission/check is still required for the remaining live-input acceptance.

The AppKit menu correctly uses common runloop timers by construction, but this is not equivalent to measured live menu interaction. AVAudioRecorder writes mic audio during recording but crash-finalized microphone WAV-header recovery has not been experimentally proven. Mac PCM writer checkpoints its header and data; no guarantee of zero hardware-crash loss.

## Review fixes and tests

Independent static review identified duplicate-instance lazy initialization, cancellation during suspended microphone startup and retry overwriting previous final text / derived graph downgrades. These were corrected. Isolated regression tests cover suspended start cancellation without microphone access, retained prior text and derived-index write failure, saved/failed/restarted history, single-flight retry, source preservation, PCM timeline mixing, subprocess output/cancellation and readiness split.
