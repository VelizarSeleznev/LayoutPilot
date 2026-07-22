# Instant Globe Layout Switching

## Goal

Add an opt-in LayoutPilot setting that replaces macOS's delayed Globe-key input-source picker with immediate cycling through every enabled macOS keyboard input source. The input source must change on the Globe key's down edge. A small custom indicator appears afterward, but rendering it must never delay the switch.

## User Experience

The Layout Switching section in Settings gains an `Instant Globe switching` toggle. It is off by default for new and existing configurations. Its help text explains that LayoutPilot takes over the Globe/Fn key while the option is enabled.

When enabled:

1. Pressing Globe immediately activates the next enabled keyboard input source.
2. The source list uses the same order macOS exposes for selectable, enabled keyboard input sources.
3. After the activation request has completed, a compact indicator shows the new language and layout, such as `EN · U.S.`.
4. The indicator appears near the upper-right corner of the screen containing the pointer, below the menu bar, and fades away after 0.7 seconds.
5. The indicator is nonactivating, click-through, and never takes keyboard focus.

The system Globe picker and Globe-triggered voice-input behavior are suppressed while this option is enabled. This is a deliberate dedicated-key mode: using Globe as an Fn modifier can still cause the layout to switch on the initial press. The user can restore normal system behavior by disabling the option.

## Input Semantics

The existing signed Core Graphics event tap will also subscribe to `flagsChanged` events. A small state machine recognizes the physical Fn/Globe key and tracks whether it is currently down.

- A transition from up to down performs exactly one cycle and consumes the Globe event.
- Repeated down signals while the key remains held are consumed without cycling again.
- The up transition clears the held state and is consumed so macOS does not interpret a completed Globe gesture.
- A long hold therefore cycles once and does not start voice input.
- Two distinct press/release sequences cycle twice and do not start the system double-press action.
- Other keyboard events received while Globe is held do not cause another cycle.
- When the option is disabled, all Globe events pass through unchanged.

Tap-disable recovery must also clear the held state. This prevents a recovered tap from treating a later Globe press as part of a stale gesture.

## Components

### Configuration and Settings

`LayoutPilotConfiguration` stores a backward-compatible `instantGlobeSwitchingEnabled` Boolean that decodes to `false` when absent. `LayoutPilotStore` exposes a focused setter. `SettingsView` places the toggle under Layout Switching with concise dedicated-key guidance.

`LayoutPilotAppState` synchronizes the configuration value into the global keyboard service at launch and whenever configuration changes.

### Globe Event State Machine

A small, independently testable state type converts Globe press/release inputs into one of three outcomes: pass through, consume, or consume and cycle. Keeping this policy separate from the event-tap callback makes held, repeated, disabled, and double-press behavior deterministic in unit tests.

The event-tap callback does only latency-sensitive work: identify the Globe transition, consult the state machine, and request a cycle. The source activation finishes before the callback returns so typing immediately after Globe uses the new layout. Overlay presentation is dispatched separately and does not participate in the activation path.

### Input Source Cycling

A focused cycler owns a cached snapshot of enabled, selectable keyboard input sources. It finds the current source, selects the following source with wraparound, and returns the selected source's display metadata.

The cache is populated at service startup and refreshed when `NSTextInputContext.keyboardSelectionDidChangeNotification` fires. On a cycle failure caused by a stale or missing current source, the cycler refreshes and retries once. If the refreshed list still does not contain the current source, the first source in that list is the deterministic target. The hot path does not enumerate the entire source list twice as the current general-purpose activation method does.

If fewer than two selectable sources exist, the event remains consumed in dedicated-key mode but no activation or misleading indicator occurs.

### Language Indicator

A main-actor controller owns one borderless `NSPanel`. The panel uses a high floating level, does not become key or main, ignores mouse events, and is excluded from normal window switching. Its SwiftUI content is a compact material pill containing an uppercase language code and localized source name.

Each successful switch replaces the displayed content, cancels any pending dismissal, and restarts the short fade timer. Rapid presses therefore show only the latest selected source without stacking panels or delaying switching.

## Data Flow

1. The Event Tap receives the Globe/Fn `flagsChanged` down transition.
2. The state machine returns `consumeAndCycle`.
3. The cycler synchronously activates the next cached input source.
4. The callback consumes the Globe event, preventing the system action.
5. On success, an asynchronous main-actor task tells the indicator controller what was selected.
6. Existing input-source change observers update LayoutPilot automation state normally.

## Failure Handling

- If Accessibility permission is missing or the tap cannot be created, existing permission and recovery behavior remains responsible for restoring the event tap; system behavior is not falsely reported as replaced.
- If the cached source list is stale, the cycler refreshes and retries once.
- If selection still fails, the event is consumed to avoid launching a competing system action, no success indicator is shown, and the failure is logged.
- The feature must not alter code-signing settings or introduce another permission model.

## Testing and Verification

Unit tests cover:

- backward-compatible configuration decoding defaults the option to off;
- the store setter persists the option;
- disabled mode passes Globe transitions through;
- a press cycles once, repeats while held do not cycle, and release resets the state;
- a long hold produces one cycle;
- two complete presses produce two cycles;
- non-Globe events pass through;
- cycling follows the enabled-source order and wraps at the end;
- zero or one available source produces no selection;
- an unknown current source refreshes and selects the first enabled source;
- indicator presentation is requested only after successful activation.

Repository verification follows the required signed lifecycle:

1. Run `xcodegen`.
2. Run `xcodebuild -project LayoutPilot.xcodeproj -scheme LayoutPilot -derivedDataPath .build test`.
3. Run `./script/build_and_run.sh run` and manually verify immediate press, hold, double press, rapid presses, overlay placement, and disabling the option.

The generated Xcode project and `.build` artifacts are not committed.

## Scope

This change does not add user-defined layout ordering, alternative hotkeys, overlay customization, or a general-purpose keyboard remapping engine. It uses the enabled macOS input-source list and one opt-in dedicated Globe behavior.
