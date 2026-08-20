# DICTATOR — Local ASR Benchmark (Apple M4, 16 GB, macOS 15.5)

Date: 2026-08-20 · Audio: real DICTATOR takes (16 kHz mono, Dictations archive)
Metrics: wall-clock, warm model loaded (except where noted). RTF = seconds audio / seconds compute (higher = faster).

## Results — 30.5s German take (`000309`)

| Engine | Model | Warm infer | RTF | German output |
|---|---|---|---|---|
| whisper.cpp (Metal) | ggml large-v3-turbo | **10.8s** | 2.8× | ✅ de, p=0.999 |
| parakeet-mlx | parakeet-tdt-0.6b-v2 | **4.8s** | 6.3× | ❌ TRANSLATES to English |
| mlx-qwen3-asr | Qwen3-ASR-0.6B | 19.9s | 1.5× | ✅ best quality |
| WhisperKit (current, in-app) | large-v3_turbo | ~30s (65s incl. delivery) | ~1× | ✅ de locked |

## Results — 53.3s German take (`000305`)

| Engine | Model | Warm infer | German output |
|---|---|---|---|
| whisper.cpp | large-v3-turbo | 11.0s (4.8× RTF) | ✅ |
| parakeet-mlx | tdt-0.6b-v2 | 4.6s (11.6× RTF) | ❌ English |
| mlx-qwen3-asr | Qwen3-ASR-0.6B | ~20s | ✅ best quality |

## Results — 1.6s English take (`000308`)

| Engine | Warm infer | Output |
|---|---|---|
| parakeet-mlx | 1.0s | "Okay." ✅ |
| mlx-qwen3-asr | 4.4s (first run w/ model already warm) | ✅ |

## Quality spot-check (verbatim, take 000309)

- **Qwen3-ASR:** "Mein Problem hier ist, dass jeder Channel immer nur eine aktive Session ist… Glaubst du, wir können Bus umbauen…" — near-perfect German, punctuation, casing.
- **whisper.cpp:** comparable to WhisperKit (same model weights).
- **Parakeet:** "My problem here is that channel immanuity achieved that function when Jeda thread a active session…" — English translation WITH errors. Unusable for German under the language-lock rule.

## Verdict

1. **Parakeet TDT (parakeet-mlx)** — fastest by far (6–12× RTF) but **translates German→English** with the v2 multilingual checkpoint on parakeet-mlx; no language-force API exposed (`generate(mel, decoding_config=…)` has no language param). EN-only until upstream adds it. **Not usable for DE.**
2. **Qwen3-ASR-0.6B (mlx-qwen3-asr)** — best German quality of all tested (better than Whisper large-v3-turbo), 1.5× RTF warm ≈ current WhisperKit speed. Adds: timestamps, diarization, streaming mode, `--language` flag.
3. **whisper.cpp** — 2.8–4.8× RTF, drop-in language auto-detect (p=0.999), same weights as today → identical quality, ~3–5× faster than WhisperKit.

## Recommendation for DICTATOR

- **Full-file pass:** switch engine to **whisper.cpp** (C API via SPM `whisper_cpp` product or bundled dylib) — same large-v3-turbo quality, 3–5× faster, exact language auto-detect, no translation risk.
- **Optional quality mode:** Qwen3-ASR for takes where max accuracy matters (Python sidecar or MLX Swift package); slower but best DE.
- **Parakeet:** watch upstream for language forcing; revisit for EN-only fast mode.

Bench environment: /tmp/asrbench (parakeet-mlx 0.5.x, mlx-qwen3-asr 0.3.5), /tmp/whisper.cpp (ggml b4938, Metal).
