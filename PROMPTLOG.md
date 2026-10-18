# Promptlog

## 2026-10-18 — Emin — v0.9.33 candidate — recorded by Hermes

- Save approximately 128 kbit/s audio, not bulky WAV archives. — #15 / #16
- After successful transcription keep text; offer historical audio cleanup. — #15 / #16
- Update DICTATOR after implementation. Source `e063b216`; final verification/install pending. — #16

```mermaid
flowchart LR
  Request[Compact recordings] --> Candidate[e063b216 source candidate]
  Candidate --> Verify[Final macOS verification approval]
  Verify --> Install[Idle-only update]
```
