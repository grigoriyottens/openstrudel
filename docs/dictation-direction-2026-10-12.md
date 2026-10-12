# Local dictation: proposed direction, 12 October 2026

## Decision

Reuse OpenRamble's recording and recognition approach inside OpenStrudel. Do not require people to install, open or link a second application. Keep the existing native Mac interface. This is a proposal and source investigation, not a shipped replacement for Apple dictation.

One microphone button should offer an optional model download on first use, showing the actual size and download progress. Later presses record immediately; finished speech segments are transcribed while recording, and Stop finishes the last segment. Text goes into the current draft for review and sending. Cancellation preserves the previous draft, a recognition failure preserves the recording for retry, and changing conversations must not insert text into the wrong draft. No audio should leave the current device for this feature, even when the employee runs on a VDS.

The interface language must not force the spoken language. People using the English interface may dictate in Russian or mix languages. Avoid a model picker in the normal flow. Reusing another app's cache through a fragile path is not worth a second setup scenario; a verified import can be considered later only if duplicated storage is a measured problem.

## What exists today

OpenStrudel's `VoiceCapture.swift` records locally and invokes Apple's `DictationTranscriber` after Stop. It is optional, offers language assets and includes recovery, but does not incrementally transcribe during recording. The earlier five-language smoke used synthetic recordings, not a quality evaluation of natural speech or live microphone capture.

OpenRamble source was inspected at `origin/main` commit `b24a890b85e4bde51df0d4aa93a24724b1582df5`, without changing its working branch:

- `Packages/DictationCore/…/StreamedSegmentRecognizer.swift`: ordered recognition of finished segments, one decoder at a time, cancellation and complete-recording fallback when a segment fails.
- `Packages/LocalASR`: pinned transcribe.cpp 0.2.3, Parakeet TDT 0.6B v3 Q8_0, approximately 740 MB of weights. Model staging, checksum validation and atomic promotion are already implemented.
- The pinned XCFramework contains Mac, iOS and iOS Simulator slices. The current Swift package declares macOS; adding iOS remains integration and device-testing work.
- `core/ramble-engine` and `apps/desktop`: a Rust wrapper around the same runtime and a Tauri shell. Mac ARM uses Metal; current Windows/Linux configuration uses CPU. GPU acceleration there must be measured and packaged, not assumed.

The installed OpenRamble CLI successfully transcribed the same synthetic Russian, English, French and Spanish fixtures on this Mac. This proves the available engine can process those files. It does not prove better natural-speech quality than Apple.

## Model choice

[Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) supports 25 European languages, including Russian, English, French and Spanish. Hebrew is not among them. It cannot be the only model for the five languages OpenStrudel exposes.

The existing [transcribe.cpp 0.2.3 runtime](https://github.com/handy-computer/transcribe.cpp/tree/v0.2.3) also supports [Whisper](https://github.com/handy-computer/transcribe.cpp/blob/v0.2.3/docs/models/whisper.md). Whisper's [language list includes Hebrew](https://github.com/openai/whisper/blob/main/whisper/tokenizer.py). A multilingual Whisper Large v3 Turbo candidate would keep a single engine and model family across all five languages. Prefer that simpler arrangement if the measured latency and memory are acceptable; do not silently add two large model downloads.

OpenRamble's existing 9 October benchmark is useful but narrower: on an M4 Pro with 24 GB, 200 short public RU/EN recordings gave Parakeet word error rates of 5.95%/5.57%, versus 5.15%/5.10% for whisper.cpp Large v3 Turbo F16. Median complete CLI runs were 0.359 s versus 1.478 s. These are different engine/model combinations and do not predict the candidate quantized model's result. Long mixed-language samples also exposed omissions in Parakeet. Faster is not automatically more accurate.

Before changing the default, run Apple, the existing Parakeet implementation and the chosen quantized Whisper build on the same consented natural-speech corpus: all five languages, mixed RU/EN, names, dates, numbers, negation, quiet and noisy rooms, and 15–120 second messages. Record text errors and omissions, Stop-to-draft median/p95, memory, offline behavior, cancellation and interruption recovery. No unrelated private recording history should be harvested for this comparison.

## Platform plan

| Platform | Reuse | Work still required |
| --- | --- | --- |
| macOS | Native composer; OpenRamble segment recorder/model download/decoder concepts | Integrate the portable decoder, select the model using the comparison above, test actual microphone input and permission/recovery states |
| iOS | Existing native UI and compatible C runtime slices | Audio-session interruptions, memory/thermal limits and model download/resume on a physical iPhone; Simulator alone is insufficient |
| Windows/Linux desktop | Existing web interface in a thin desktop shell; portable runtime, with OpenRamble's Rust/Tauri code as a reference | Native microphone/permissions, packaging, CPU baseline and measured optional GPU support on real machines |
| Browser | Current web interface and attachment flow | A separate offline browser speech implementation and performance proof; do not present browser speech APIs as reliably local |

Employee hosting stays independent of these choices. Mac, VDS and future desktop clients should use the same Home protocol; dictation produces a draft on the device where the person is speaking.

Telegram voice recognition is a separate path: `src/voice.ts` invokes the installed OpenRamble CLI on Mac and bundled whisper.cpp on Linux. That existing server feature is not proof of local composer dictation on Windows or in a browser.

## Release scope

No ASR engine replacement was published during this investigation. Current Apple dictation remains in build 35. A proposed portable implementation should ship only after the quality and platform checks above, without introducing another compulsory application or forcing a rewrite of the Mac interface.
