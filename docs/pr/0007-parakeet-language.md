# #0007 — Parakeet language, English-only cleanup, transcript history pages, Groq and preset pages

- Branch: `jv.parakeet-language` · Merged: 2026-10-17 · Commits: `67962a9`

## Why
Not recorded beyond the feature list; the changes make non-English dictation safe, make history browsable, and give providers and presets their own pages.

## What changed
- **Parakeet language:** Language picker (default Automatic, no hint). A chosen language passes FluidAudio's `language:` hint, which only keeps output in that alphabet (Latin, Cyrillic, Greek) and doesn't separate languages sharing one. 25 languages in `ParakeetLanguage` (Core).
- **English-only cleanup:** full deterministic cleanup runs only on English (picked for Parakeet, or detected / unidentifiable on Automatic or Apple's model). Language detection ignores filler words. Dictionary corrections still apply to all languages.
- **Transcripts, 10 per page:** `LIMIT`/`OFFSET` paging with Previous/Next; moves back if history is purged under you.
- **Transcript detail page:** steps Speech-to-Text, Deterministic Cleanup, LLM Formatting, each with text, words changed, model, timing, tokens; skipped, failed or purged steps are labeled.
- **`cleaned_transcriptions` table:** cleaned text stored per dictation (NULL if cleanup didn't run). Older dictations show "not recorded". Shown in Storage and included in Purge All.
- **Groq configuration page** (API key, model, pricing) reached from a Configuration row in Models; `FormattingProvider.hasConfiguration` and `ProviderConfigurationView` are the extension points for other providers.
- **Edit Preset page** with Reset to Preset (Clear for Custom). Choosing another preset still replaces edited text.
- `BackBar` back arrow plus ⌘[ on the new pages, because the toolbar back button doesn't reliably appear in a navigation stack nested in the split view.

## Files touched
- Core: `ParakeetLanguage.swift`, `DictationStages.swift`, `Pagination.swift`, `DeterministicCleanup.swift`, `TranscriptCleaner.swift`, `FormattingModel.swift`, `PromptPresets.swift`
- App: `TranscriptionsView.swift`, `TranscriptionStore.swift`, `GroqConfigurationView.swift`, `ProviderConfigurationView.swift`, `PresetEditorView.swift`, `ModelsView.swift`, `ParakeetTranscriptionService.swift`, `StorageView.swift`

## Decisions & trade-offs
- Language hint is deliberately weak; Automatic is the default.

## Tests
335 tests passed (`ParakeetLanguageTests`, `PaginationTests`, `DictationStagesTests`, `FormattingProviderTests`, plus new cases). All manual checks done.

## Follow-ups / known gaps
PR #8 adds stepping between transcripts and OpenRouter; PR #11 notes language detection is unreliable on very short phrases.
