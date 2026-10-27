# How Parakeet is used

Notes on how TalkToMyMac runs the Parakeet speech-to-text model: the FluidAudio API, the
settings it accepts, and what the app actually passes. Written against FluidAudio 0.17.7.

## Overview

Parakeet runs through **FluidAudio** (v0.17.7), a Swift package that runs NVIDIA's
Parakeet TDT 0.6B v3 as a Core ML model on the Neural Engine. The app wraps it in
`ParakeetTranscriptionService` (`Sources/TalkToMyMac/ParakeetTranscriptionService.swift`).

Almost every FluidAudio setting is left at its default. The only thing the app passes per
recording is the audio and an optional language hint.

## How it runs

There are three stages, each a FluidAudio call:

1. **Download:** `AsrModels.download(to:version: .v3, progress)` saves the files to
   `~/Library/Application Support/TalkToMyMac/Models/parakeet-tdt-0.6b-v3-coreml`.
2. **Load:** `AsrModels.load(from:version: .v3)`, then `AsrManager(config: .default)` and
   `manager.loadModels(models)`. The model takes memory only between `load()` and
   `unload()`; `unload()` calls `manager.cleanup()`.
3. **Transcribe**, once per recording:
   - `TranscriptionRouter.swift` calls
     `transcribe(samples:sampleRate:language: settings.parakeetLanguage)`.
   - The audio is converted to 16 kHz mono Float32 with `AudioFormatConverter`.
   - A new `TdtDecoderState.make()` is created each time, so nothing carries over between
     dictations.
   - `manager.transcribe(samples, decoderState: &state, language: hint)` returns an
     `ASRResult`. The app keeps only the trimmed `.text`; empty text counts as
     "heard nothing".

## The API and what the app passes

### `AsrModels.load(...)`: model loading

| Parameter | Options | App passes |
|---|---|---|
| `version` | `.v2`, `.v3`, `.redux`, `.ultra`, Phonon-2 (all v3 variants except v2) | `.v3` |
| `configuration` | an `MLModelConfiguration` | default |
| `encoderPrecision` | `.int8` (default), or a larger re-quantized encoder (568 MB vs 425 MB) that avoids a known token-corruption bug (issue #760) | default `.int8` |
| `encoderComputeUnits` | Neural Engine / GPU / CPU | default |
| `progressHandler` | load progress callback | not passed |

### `ASRConfig`: given to `AsrManager(config:)`

The app passes `.default`, so every field below is at its default.

| Field | Default | What it does |
|---|---|---|
| `sampleRate` | 16000 | Expected input rate |
| `tdtConfig` | `.default` | Decoder settings (next table) |
| `parallelChunkConcurrency` | 4 | How many chunks of long audio are processed at once |
| `streamingEnabled` / `streamingThreshold` | true / 480,000 samples (~30 s) | Disk-backed processing for large files; applies only to the file-URL `transcribe` |
| `melChunkContext` | nil (off for v3) | Extra audio context at the start of each chunk of long audio |
| `dualDecodeArbitration` | false | Opt-in: tries chunk splits before committing (long audio) |
| `seamGapRepair` / `seamGapRepairMinGapSeconds` | true / 1.5 | Repairs words dropped where chunks join |

### `TdtConfig`: decoder settings

These are tied to the model's structure; changing them mostly breaks things rather than
tuning anything.

| Field | Default |
|---|---|
| `maxSymbolsPerStep` | 10 |
| `durationBins` | `[0,1,2,3,4]` |
| `blankId` | 8192 |
| `boundarySearchFrames` | 20 |
| `maxTokensPerChunk` | 150 |
| `consecutiveBlankLimit` | 5 |
| `includeTokenDuration` | true |

### `AsrManager.transcribe(...)`: per call

- **Inputs**, as overloads: `[Float]` samples (what the app uses), `AVAudioPCMBuffer`, a
  file `URL`, or `transcribeDiskBacked(url)`.
- **`decoderState: inout TdtDecoderState`** lets decoding continue across calls if you
  reuse it. The app makes a new one each time.
- **`language: Language?`**
  - It's a script filter, not true language selection: it skips tokens outside the
    language's script (Latin, Cyrillic, Greek). It fixes mixed-script output but can't tell
    apart languages that share a script.
  - The app maps its `ParakeetLanguage` enum (25 European languages,
    `Sources/TalkToMyMacCore/ParakeetLanguage.swift`) to FluidAudio's `Language` by ISO
    code, and passes nil for "Automatic".
- **`transcriptionProgressStream`** emits progress for audio over about 15 s. The app
  doesn't use it.

### `ASRResult`: what comes back

| Field | Notes |
|---|---|
| `text` | The only field the app keeps |
| `confidence` | Overall confidence |
| `duration` / `processingTime` | Audio length and time taken |
| `rtfx` | Speed vs. real time |
| `tokenTimings` | Per-token start/end/confidence; `buildWordTimings(from:)` turns them into word timings |
| `performanceMetrics` | Timing breakdown |
| `ctcDetectedTerms` / `ctcAppliedTerms` | Filled only when vocabulary boosting is on |

## Available but unused

- **Vocabulary boosting:** `configureVocabularyBoosting(vocabulary:ctcModels:config:)`
  biases recognition toward custom terms, using a `CustomVocabularyContext` plus a separate
  CTC model. It's offered on `SlidingWindowAsrManager`, `UnifiedAsrManager` and the
  streaming manager, not on the plain `AsrManager` the app uses. This is the model-side
  counterpart to the dictionary, which today only fixes words after transcription.
- **Streaming managers** (`SlidingWindowAsrManager`, `StreamingUnifiedAsrManager`)
  transcribe while you speak instead of after recording stops.
- **Per-token confidence and timings**, which could flag low-confidence words.

## Where to look in FluidAudio

Checked out under `.build/checkouts/FluidAudio/Sources/FluidAudio/`:

- `ASR/Parakeet/AsrTypes.swift`: `ASRConfig`, `ASRResult`, `TokenTiming`
- `ASR/Parakeet/SlidingWindow/TDT/AsrManager.swift`: `transcribe` overloads
- `ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift`: `download`, `load`, `AsrModelVersion`
- `ASR/Parakeet/SlidingWindow/TDT/Decoder/TdtConfig.swift`: decoder settings
- `ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift`: vocabulary boosting
- `Shared/TokenLanguageFilter.swift`: the `Language` enum
