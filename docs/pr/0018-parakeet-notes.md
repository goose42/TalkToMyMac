# #0018 — Add notes on how Parakeet is used

- Branch: `jv.parakeet-notes` · Merged: not yet · Commits: 0a9a4a0

## Why
Not recorded. The notes were an untracked file in the working tree, committed on request.

## What changed
Docs only. Adds `docs/parakeet_notes.md`, describing how the app runs Parakeet through FluidAudio 0.17.7:
the download/load/transcribe stages, the settings the app passes (almost all defaults, only the audio and an
optional language hint per recording), the API tables, and unused options (vocabulary boosting, streaming).

## Files touched
- Docs: `docs/parakeet_notes.md`

## Decisions & trade-offs
Written against FluidAudio 0.17.7; may go stale on upgrade.

## Tests
None (docs only).

## Follow-ups / known gaps
Re-check against FluidAudio when the dependency is bumped.
