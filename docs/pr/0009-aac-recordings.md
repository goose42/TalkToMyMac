# #0009 — Save recordings as AAC after the pipeline and play them from transcripts

- Branch: `jv.aac-recordings` · Merged: 2026-10-17 · Commits: `bf34024`

## Why
The mic tap wrote a WAV during recording (disk I/O on the hot path) and the 48 kHz WAVs were large.

## What changed
- No disk I/O while recording. After the pipeline finishes (after the paste, any outcome), `RecordingArchiver` encodes the in-memory samples to 16 kHz mono AAC at 32 kbps (`.m4a`) on a utility-priority queue. About 25x smaller. Files are written under a hidden name and renamed when complete. Esc-discarded recordings and pronunciation-practice clips are never written.
- `RecordingArchiving` protocol in Core is called from `RecorderController.processRecording`.
- Each dictation has a `recordingID` that is both its transcript row ID and the file name (`recording-<id>.m4a`), so no schema change. The detail page's Speech-to-Text section has a play/pause row with scrubber and times; playback stops on stepping or leaving the page.
- `scripts/compress-recordings.sh`: converts old WAVs with `afconvert`, keeps modification dates, deletes a WAV only after the `.m4a` duration matches; `--dry-run`, `--keep`, re-runnable.
- `scripts/link-recordings.sh`: renames randomly named recordings to transcript IDs by duration (±0.3 s) and timing (within 2 min), closest first, one-to-one; reads the DB read-only and logs renames so they can be undone. 368 of 420 linked on a copy of real data.
- Storage counts and purges `.m4a` and leftover `.wav`.

## Files touched
- Core: `RecorderController.swift`, `Protocols.swift`, `Models.swift`
- App: `RecordingArchiver.swift`, `RecordingPlayer.swift`, `AudioCapture.swift`, `TranscriptionsView.swift`, `StorageView.swift`
- Scripts: `scripts/compress-recordings.sh`, `scripts/link-recordings.sh`

## Decisions & trade-offs
- The archived audio is raw, pre-denoise samples.

## Tests
384 tests passed (10 new archive and `recordingID` tests covering every exit path). AAC settings verified with `afinfo`; both scripts exercised on scratch copies.

## Follow-ups / known gaps
None recorded.
