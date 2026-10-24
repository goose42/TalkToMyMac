# #0016 — Document every PR in docs/pr

- Branch: `jv.pr-history-docs` · Merged: pending · Commits: see PR

## Why
Give agents a readable trace of the repo's history: why each change was made, not just what the diff shows.

## What changed
- `CLAUDE.md` has a new **PR docs** rule: every PR adds `docs/pr/NNNN-<slug>.md`. `docs/pr` is listed in the layout.
- `docs/pr/README.md` defines naming and the template.
- Backfilled `0000-initial-history.md` and `0001`–`0015` from PR descriptions, commits and diffs. Where rationale wasn't recorded, the files say "Not recorded." instead of guessing.

## Files touched
- `CLAUDE.md`, `docs/pr/**`

## Decisions & trade-offs
- Number-prefixed names sort chronologically; the PR number is only known after the PR is created, so the doc is committed to the branch right after `gh pr create`.
- The existing `docs/parakeet_notes.md` was left alone.

## Tests
None (docs only). `make test` run as a sanity check.

## Follow-ups / known gaps
Backfilled files are reconstructions and may miss context that lived only in conversations.
