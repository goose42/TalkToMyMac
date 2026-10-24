# #0002 — Learn a dictionary term's "heard as" forms from a voice recording

- Branch: `jv.voice-dictionary-entries` · Merged: 2026-10-14 · Commits: `318d274`

## Why
Users had to type the mis-transcriptions ("heard as" / `soundsLike`) for each dictionary term by hand. Recording the term lets the app discover real mis-hearings.

## What changed
A **Record Pronunciation…** button in a dictionary entry's "Heard as" section. The user records the term alone and then in the carrier sentence "I'm working with ___ today." Both recordings are transcribed and new mis-transcriptions are added to the entry's `soundsLike` automatically.

Each recording is transcribed in 7 versions (original, 0.9× and 1.1× speed, pitch ±300 cents at the same tempo, band-limited 300–3400 Hz, white noise at 15 dB SNR). The engine is asked for alternative transcriptions (`.transcriptionWithAlternatives`).

Candidate filtering: carrier words stripped for the sentence take; trimmed and de-capitalized ("Hotel." → "hotel"); drops the written form, already-listed forms and anything over 4 words; ranked by how many versions produced it; max 8.

## Files touched
- Core: `AudioVariations.swift`, `PronunciationProbe.swift`, `DictionaryEditor.addSoundsLike`, `Protocols.swift` (`SpeechTranscribing.transcribeAlternatives`, `PitchShifting`)
- App: `PronunciationRecorderView.swift`, `TimePitchShifter.swift` (`AVAudioUnitTimePitch`, offline), `SpeechTranscriptionService.swift` (shared analysis path), `DictionaryView.swift`
- Tests: `AudioVariationsTests`, `PronunciationProbeTests`, `DictionaryEditorTests`

## Decisions & trade-offs
- `transcribeAlternatives` has a default implementation wrapping `transcribe`, so other engines keep working.
- Recordings made in the sheet are deleted right after use.

## Tests
215 tests passed; release build succeeded. Not run by hand in the app at merge time. Speech-engine, pitch-shifter and sheet code are untested because the test target cannot import the app target.

## Follow-ups / known gaps
PR #13 makes the sheet respect the selected microphone.
