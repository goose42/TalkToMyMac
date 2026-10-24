# #0011 — Clean up short dictations; quit the app before building

- Branch: `jv.short-dictation-cleanup` · Merged: 2026-10-18 · Commits: `282b0ca`, `c28a302`

## Why
Short utterances ("Sounds good.") read better in chat-style text without a trailing period and capital. For the Makefile change, the reason is not recorded; the app should be quit before it is rebuilt.

## What changed
- New `ShortDictation` step in the English branch of `DeterministicCleanup.apply`: when the cleaned text is two words or fewer, drop the trailing period and lowercase the first letter. It runs before dictionary replacement so dictionary terms keep casing ("Github please." → "GitHub please"). Keeps `?`, `!`, ellipses; leaves "I", "OK" and mixed-case words like "iPhone".
- `make run` and `make install` quit the running app before building, not after.

## Files touched
- Core: `ShortDictation.swift`, `DeterministicCleanup.swift`
- Build: `Makefile`
- Tests: `ShortDictationTests`, `DeterministicCleanupTests`

## Decisions & trade-offs
Known limitations: language detection is unreliable on very short phrases ("Call Sam." detects as Polish), so with Parakeet on Automatic such dictations skip full cleanup, including this step (choosing English avoids it). A short dictation starting with a name not in the dictionary is lowercased ("Sam said." → "sam said").

## Tests
412 tests passed; `make -n` shows the quit step first; manually dictated "Sounds good." and got "sounds good".

## Follow-ups / known gaps
See limitations above.
