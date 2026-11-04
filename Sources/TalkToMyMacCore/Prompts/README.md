# Prompts

Every `.md` file in this folder except this README is a built-in prompt. The
`PromptCompilerPlugin` build plugin compiles them into `PromptLibrary`, one `public static let`
per file (`clean-up.md` → `PromptLibrary.cleanUp`, also `PromptLibrary.all["clean-up"]`).
The whole file is the prompt, minus one trailing newline, so don't add front matter or headings
that aren't meant for the model.

| File | Used by |
| --- | --- |
| `coding.md` | `PromptPreset.coding` (the default preset) |
| `clean-up.md` | `PromptPreset.cleanUp` |
| `verbatim.md` | `PromptPreset.verbatim` |
| `email.md` | `PromptPreset.email` |
| `code-comment.md` | `PromptPreset.codeComment` |
| `dictionary-entry.md` | `DictionaryEntryPrompt.instructions` |

`PromptPresetTests.testCompiledPromptsMatchPinnedText` pins each prompt's SHA-256. A user's
saved prompt counts as "edited" whenever it differs from the built-in text, so changing a prompt
changes that for everyone. Update the hash only when you mean to change the prompt, and measure
the change with the evals first (`evals/README.md`).

## User turn

The formatting prompts are the system instructions. The user turn is only the transcript,
wrapped in tags by `FormattingInstructions.userPrompt(transcript:)`:

```
<transcript>
{{TRANSCRIPT}}
</transcript>
```
