# Architecture

LayoutPilot is split into two layers:

## `LayoutPilotCore`

Reusable logic with no UI assumptions:

- configuration models
- rule persistence
- input source discovery and switching
- the automation engine that reacts to frontmost app changes

## `LayoutPilot`

Native macOS UI:

- `WindowGroup` main dashboard
- `Settings` scene
- `MenuBarExtra`
- split-view navigation and editors for rules and profiles

## Idle and keystroke cost

LayoutPilot holds a session-wide `CGEvent` tap and runs from login to logout, so both its idle behaviour and its per-keystroke work are load-bearing.

The active browser URL drives website rules, and resolving it costs an Apple Event round trip that wakes the browser process as well. `BrowserActivityObserver` therefore watches the browser through accessibility notifications — focused-window and main-window changes on the application element, title and focused-element changes on the focused window — and coalesces a burst of them into one lookup 300ms later. `LayoutAutomationEngine` keeps a 20-second timer with 5 seconds of leeway purely as a safety net for in-page navigation that never changes the window title.

`SmartInputService` answers "is this token a snippet trigger, or a prefix of one?" on every keystroke. It does so against `SnippetIndex`, a pair of lookup tables keyed by lowercased trigger and by lowercased proper prefix, rebuilt only when the snippet configuration changes. Per-application permission is resolved once per frontmost application into a cached set of snippet IDs. Neither path may scan the snippet list or construct a `SnippetApplicationScope` per keystroke. The event tap's watchdog is a backstop only — the ordinary ways a tap dies arrive through the tap callback itself — so it runs every 5 seconds with matching tolerance.

`SmartInputLearningStore` holds roughly a megabyte of learned words once it reaches its 2,000-word limit, and every save rewrites all of it. Writes are debounced 30 seconds, encoded compactly without sorted keys, and performed off the lock so the event tap is never blocked behind a serialization. `AppDelegate` forces a synchronous flush on termination and before sleep.

## Extension points

The project is intentionally structured so later work can add:

- extra matching strategies for rules
- launch-at-login integration
- richer diagnostics and logging
- local LLM calls for assisted rule creation or classification

