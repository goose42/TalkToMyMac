# #0014 — Add a widget menu to the floating indicator

- Branch: `jv.widget-menu` · Merged: 2026-10-22 · Commits: `ce962be`

## Why
Not recorded. The indicator had no quick actions.

## What changed
- Left-click the plain dot, or right-click / Control-click any time, to open a menu styled like the replacement picker (translucent black, pale text).
- Items: **Copy Last Dictation** (greyed out with no history), **Start/Stop Recording**, **Hide for 1 Hour**.
- Hiding lasts an hour or until the next recording starts, whichever is first. It is in memory only (relaunch shows the dot). The Settings "Show floating indicator" switch is separate and unchanged.
- Left-click while a notice or replacement review is showing is unchanged.

## Files touched
- Core: `WidgetMenu.swift`, `IndicatorSnooze.swift`, `IndicatorClick.swift`
- App: `FloatingIndicator.swift` (menu panel, shared `makeOverlayPanel()` and `positionAbove(_:size:)` with the picker, click routing), `AppDelegate.swift` (copy/toggle callbacks; wakes the indicator in `setRecording(true)`)
- Tests: `WidgetMenuTests`, `IndicatorSnoozeTests`, `IndicatorClickTests`

## Decisions & trade-offs
Decision logic is pure Core types with tests written first; the app target only does rendering and wiring.

## Tests
444 tests passed; release build compiles; menu opening, each item, hide and early wake, and the replacement picker all checked by hand.

## Follow-ups / known gaps
None recorded.
