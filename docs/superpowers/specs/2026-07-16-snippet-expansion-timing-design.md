# Snippet Expansion Timing Design

**Date:** 2026-07-16
**Status:** Implemented

## Goal

Give users one global choice for when text snippets expand while making immediate expansion the default. A single Backspace immediately after an expansion must restore the original trigger. Separately, new configurations should start with spelling autocorrect disabled without changing an existing user's saved preference.

## Scope

- Add one global snippet expansion mode with two values: `Immediately` and `After Space`.
- Show the setting on the Snippets screen and apply it to every enabled snippet.
- Default new and legacy configurations that do not contain the setting to `Immediately`.
- Make one Backspace undo the most recent snippet expansion in either mode.
- Default spelling autocorrect to off for new configurations and Reset only.
- Preserve explicitly saved spelling-autocorrect values during upgrades.

Per-snippet timing, automatic timing inference, and configurable undo windows are out of scope.

## Behavior

### Immediately

As soon as the buffered input exactly matches an enabled snippet trigger, LayoutPilot replaces the trigger with the snippet text. No separator is required. The final trigger keystroke is consumed as part of the expansion.

If one trigger is a prefix of another, an exact match wins and expands immediately. Users who need the longer trigger should choose non-overlapping triggers or use `After Space`.

### After Space

LayoutPilot waits until the user presses Space after an exact trigger. It replaces the trigger with the snippet text and preserves one trailing space after the replacement. Other boundaries do not expand the snippet.

### One-Backspace Undo

Immediately after either kind of snippet expansion, one Backspace removes the complete replacement and restores the exact original trigger. In `After Space`, undo also removes the space that initiated expansion. The Backspace event itself is swallowed so it does not delete a character from the restored trigger.

Any non-Backspace user input deactivates this quick undo. Snippet undo remains excluded from smart-input rejection learning.

## Configuration and Migration

Add a Codable global expansion-mode value to `LayoutPilotConfiguration`.

- Initializer default: `Immediately`.
- Missing decoded value: `Immediately`.
- Existing saved value: preserve it.

Change the spelling-autocorrect initializer default and missing-value decode default to `false`. Existing configurations that explicitly contain `true` continue to decode as enabled. `Reset to Defaults` creates a configuration with spelling autocorrect disabled.

## Interface

Add a compact global control near the Snippets master Active toggle. Its two choices are `Immediately` and `After Space`, with brief explanatory help text. The control is not repeated in the create or edit forms because it applies to all snippets.

## Runtime Design

The app state synchronizes the persisted expansion mode into `SmartInputService` alongside the existing snippet list and enabled flag.

The service keeps the current trigger buffer behavior but branches expansion by mode:

- `Immediately`: after appending a character, check for an exact eligible snippet before returning the event. Replace the trigger without a boundary.
- `After Space`: only treat the literal space character as the committing boundary for snippets. Existing Smart Danish, RU/EN, and spelling boundary processing continues to receive other boundaries normally.

Snippet replacements use the existing last-replacement record. Backspace handling special-cases replacement mode `snippet` so it performs the full undo on the first press, regardless of whether the recorded boundary is empty or a space. Non-snippet conversions keep their current boundary-first undo behavior.

## Validation

Tests cover:

- default and missing decoded expansion mode are `Immediately`;
- persisted expansion mode survives encode/decode;
- immediate exact matching and prefix behavior;
- `After Space` expands only on a literal space;
- one Backspace restores the trigger for immediate expansion;
- one Backspace restores the trigger and removes the committing space for `After Space`;
- spelling autocorrect defaults to off while an explicitly saved `true` remains on;
- existing snippet scope and security exclusions still apply in both modes.

The signed app is then built and exercised manually in a normal editable text field for both timing modes and the one-Backspace undo path.
