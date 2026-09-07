# Capture recovery and health follow-up

Base: `4beaa57901cdc3d92724b531dc4b0d551eb5ea97` (draft #11). Preserve the minimal menu/library. No merge, forced quit or active-recording writes.

## Remaining defects

1. AVAudioRecorder microphone WAVs keep unfinalized RIFF/data lengths while recording. Read-only inspection of the active recording confirmed RIFF size 4088 and data size 0 despite retained PCM payload. This is normal during capture, but there is no crash recovery path. Repair only validated mono 16 kHz PCM16 into a new derived file for inactive sessions; never rewrite the source.
2. System capture sets `received` before successful persistence. Unexpected microphone stoppage leaves global recording active. Move receipt confirmation after accepted samples, preserve combined capture warnings, and stop/save retained audio when the microphone unexpectedly stops.

## Earlier findings disposition

Duplicate-instance initialization is already guarded before lazy controller access. Fn+R has a pending startup transition. The old quick-take system-audio loss path is superseded by microphone-only Fn capture. The next meeting cancels retryable whisper.cpp transcription before starting instead of racing shared capture fields. Existing capture warnings are preserved at meeting stop, but microphone failure detection and receipt ordering still need correction.

## Verification and delivery

Use isolated PCM fixtures, real AVAudioFile decoding of repaired copies, source-byte preservation, malformed/unsupported format rejection and injected silent capture tests. Run the complete Swift suite and focused review, stage a signed build, then install only after all real recording/processing finishes. The previous idle-only installer has been paused; the running recorder remains untouched.
