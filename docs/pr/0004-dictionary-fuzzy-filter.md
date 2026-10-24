# #0004 — Add a fuzzy filter to the dictionary word list

- Branch: `jv.dictionary-fuzzy-filter` · Merged: 2026-10-16 · Commits: `9c4c2a2`

## Why
Finding a word in a long dictionary list required scrolling. Further rationale not recorded.

## What changed
A filter field at the top of Settings → Dictionary → Words narrows the list as you type, fzf-style: the query's characters must appear in order, not together ("otl" finds "OTel"). Case, diacritics and spaces in the query are ignored. It matches the written form and heard-as forms ("hotel" finds OTel), best first; a written match beats an equal heard-as match; ties keep dictionary order. UI: clear button, "No words match …" message, and a count ("Words (3 of 42)"). The filter persists while a word's details are open.

## Files touched
- Core: `FuzzyMatch.swift` (subsequence scoring: exact, prefix, word starts incl. camelCase humps, consecutive runs, fewer skips), `DictionaryFilter.swift`
- App: `DictionaryView.swift`
- Tests: `FuzzyMatchTests`, `DictionaryFilterTests` (19 new)

## Decisions & trade-offs
Scoring favors word-start and consecutive matches so results feel like fzf.

## Tests
Written first; 291 tests passed, build warning-free. UI not checked by hand at merge time.

## Follow-ups / known gaps
None recorded.
