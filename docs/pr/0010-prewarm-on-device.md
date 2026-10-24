# #0010 — Keep the on-device formatter prewarmed while recording

- Branch: `jv.prewarm-on-device` · Merged: 2026-10-18 · Commits: `7c5669c`

## Why
Apple's on-device model keeps a prewarmed prompt cached for only about 4–5 s, and formatting has a 4 s deadline (PR #8). A cold start used most of that time.

## What changed
- Each recording creates its `LanguageModelSession` when the trigger key is pressed, prewarms it with the formatting instructions and `<transcript>` prompt prefix immediately, then every 4 s via `PeriodicWarmer` (Core).
- That session formats that recording's transcript only; nothing carries over between dictations. A preset change mid-recording gets a fresh session.
- Warming continues through transcription and review and stops when the transcript is formatted, formatting is skipped, the recording is discarded, or nothing was heard.
- Warming stops by itself 2 minutes after key press so a transcript left in review doesn't keep the model busy.
- Only Apple On-Device is warmed, and only when formatting is enabled and not paused. `TextFormatting` gains no-op-by-default `beginWarming()` / `endWarming()`.

## Files touched
- Core: `PeriodicWarmer.swift`, `Protocols.swift`, `RecorderController.swift`, `FormattingInstructions.swift`
- App: `FoundationModelFormatter.swift`, `FormattingRouter.swift`

## Decisions & trade-offs
- The 2 min cap (not 1 min): the longest of 408 recordings was 86 s and 11 ran past 60 s.

## Tests
393 tests passed (`PeriodicWarmerTests`, warming tests in `RecorderControllerTests`, prompt-prefix test). Verified `prewarm` logs at about 0/4/8 s and stops after formatting.

## Follow-ups / known gaps
None recorded.
