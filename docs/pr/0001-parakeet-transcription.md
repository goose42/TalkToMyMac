# #0001 — Add Parakeet transcription and muting system audio while recording

- Branch: `jv.parakeet-transcription` · Merged: 2026-10-10 · Commits: `d84203f`

## Why
Offer a second on-device speech model besides Apple's, and keep music or meeting audio out of dictations. Further rationale not recorded.

## What changed
- **Parakeet:** NVIDIA Parakeet TDT 0.6B v3 (Core ML, Neural Engine, via FluidAudio) as an alternate engine. Download, load and unload from the Models tab.
- `TranscriptionRouter` sends each dictation to the selected engine once its model is loaded. It uses Apple's model otherwise, and as a fallback if Parakeet returns nothing.
- Each dictation records its engine in a new `transcription_model` column (earlier rows migrate to Apple's). The Instrumentation tab shows metrics per engine.
- **Mute while recording:** off-by-default toggle in Settings → General → Recording. `RecorderController` calls a `SystemAudioMuting` hook on start and stop (including Esc-discard); nothing is muted if recording fails to start.

## Files touched
- Core: `TranscriptionEngine.swift`, `RecorderController.swift`, `Protocols.swift`, `Models.swift`
- App: `ParakeetTranscriptionService.swift`, `TranscriptionRouter.swift`, `SystemAudioMuter.swift`, `ModelsView.swift`, `TranscriptionStore.swift`, `InstrumentationView.swift`
- Build: `Package.swift`, `Package.resolved` (FluidAudio dependency)

## Decisions & trade-offs
- `SystemAudioMuter` mutes the default output through CoreAudio and undoes only what it changed: an already-muted Mac stays muted, the original device is restored if the output changes mid-recording, devices without a mute control are set to zero volume then restored, and sound is restored if the app quits mid-recording.

## Tests
209 tests passed, including 6 new `RecorderController` muting tests and new `TranscriptionEngineTests`. Manual checks (music, already-muted Mac, Parakeet in Instrumentation) were left unchecked in the PR.

## Follow-ups / known gaps
The mute toggle was replaced by the Audio tab in PR #12.
