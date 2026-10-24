# #0000 — Initial history (before PR #1)

- Branch: `main` / `groq-formatting` · Dates: 2026-04-26 to 2026-10-09 · Last commit: `0be73d3`

## Why
Baseline for everything that predates the PR workflow. Reconstructed from commit messages only; rationale is not recorded.

## What changed
In rough order:
- Initial commit, `.gitignore` (2026-04-26, 2026-05-08).
- Shortcuts, prompt presets, paste delivery and stable code signing (`ac8fe5e`).
- Floating recording indicator, pipeline metrics and the Instrumentation tab (`636d29b`).
- Indicator, recordings and transcription history moved into Settings (`1c2781f`).
- LLM settings moved to a Formatting tab; LLM formatting skipped for short dictations, first by recording length and then by transcript word count (`92603b1`, `a258253`).
- Storage tab showing on-disk usage with purge controls (`e540dc0`).
- Menu-bar status items moved into Settings > General (`08d8126`).
- `make install` with app icon and `/Applications` install (`df344c8`); version 1.0.0 (`419447b`).
- Copy Last Dictation in the menu-bar dropdown (`096b0da`).
- Custom dictionary that corrects mis-heard terms during formatting (`b26404a`), with a chosen folder plus import/export (`3918a80`).
- Groq as an alternate formatting model (`781b3ee`, merged via `0be73d3`).

## Files touched
Not itemized. See `git log 0be73d3`.

## Decisions & trade-offs
Not recorded. Note that dictionary correction was initially done by the formatting LLM; PR #5 made it deterministic.

## Tests
Not recorded.

## Follow-ups / known gaps
Superseded in part by PRs #3 and #5 (cleanup and dictionary) and #6 (Settings layout).
