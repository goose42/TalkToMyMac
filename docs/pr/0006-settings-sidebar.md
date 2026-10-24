# #0006 — Settings: sidebar layout and a window that stays reachable

- Branch: `jv.settings-sidebar` · Merged: 2026-10-17 · Commits: `c319a40`

## Why
As a menu-bar-only (`.accessory`) app, clicking another app buried the Settings window with no Dock icon or Cmd-Tab entry to bring it back.

## What changed
- Settings uses a `NavigationSplitView` sidebar (like System Settings) instead of toolbar tabs; the window is resizable and minimizable.
- Sections come from a new `SettingsPane` enum in Core.
- General, Formatting and Models use `.formStyle(.grouped)`.
- While Settings is open the app switches to `.regular` and returns to `.accessory` on close; clicking the Dock icon reopens the window.
- A minimal main menu (app, Edit, Window) gives Cut/Copy/Paste/Undo in text fields, ⌘W and ⌘Q.

## Files touched
- Core: `SettingsPane.swift`
- App: `SettingsWindowController.swift`, `AppDelegate.swift`, `FormattingView.swift`, `ModelsView.swift`
- Tests: `SettingsPaneTests`

## Decisions & trade-offs
- Gotcha: the sidebar list must be tagged `id: \.self`; tagging by the enum's `String` id makes clicks silently do nothing.

## Tests
304 tests passed. Manual checks all done: each pane opens, reachable from Dock/Cmd-Tab, Dock icon goes away on close, ⌘C/⌘V/⌘W work, push-to-talk works with Settings frontmost.

## Follow-ups / known gaps
PRs #7 and #12 add panes to this sidebar.
