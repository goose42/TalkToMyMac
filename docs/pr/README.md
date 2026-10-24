# PR history

One markdown file per merged PR, so an agent can trace why the code looks the way it does without
digging through git. Read the newest files first; later PRs often supersede earlier ones.

## Naming

`NNNN-<slug>.md`: `NNNN` is the zero-padded PR number, `<slug>` is the branch name without the
`jv.` prefix (e.g. PR #5 on `jv.deterministic-dictionary` is `0005-deterministic-dictionary.md`).
`0000-initial-history.md` covers everything before PR #1.

## Template

```markdown
# #NNNN — <PR title>

- Branch: `jv.<slug>` · Merged: YYYY-MM-DD · Commits: <short shas>

## Why
The problem or need. Write "Not recorded." if unknown. Don't invent rationale.

## What changed
Behavior-level summary: what a user or caller sees now that they didn't before.

## Files touched
Key paths grouped by Core / App / Tests / Build. Not an exhaustive diff listing.

## Decisions & trade-offs
Non-obvious choices, rejected alternatives, constraints, gotchas, migrations.

## Tests
New or changed tests, and what was verified by hand.

## Follow-ups / known gaps
Limitations, untested paths, and later PRs that changed this behavior.
```

Backfilled files (#1–#15) were reconstructed from PR descriptions, commits and diffs after the fact.
