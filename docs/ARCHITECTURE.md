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

The active browser URL drives website rules, and resolving it costs an Apple Event round trip that wakes the browser process as well. `WindowActivityObserver` therefore watches the browser through accessibility notifications — focused-window and main-window changes on the application element, title and focused-element changes on the focused window — and coalesces a burst of them into one lookup 300ms later. `LayoutAutomationEngine` keeps a 20-second timer with 5 seconds of leeway purely as a safety net for in-page navigation that never changes the window title.

`SmartInputService` answers "is this token a snippet trigger, or a prefix of one?" on every keystroke. It does so against `SnippetIndex`, a pair of lookup tables keyed by lowercased trigger and by lowercased proper prefix, rebuilt only when the snippet configuration changes. Per-application permission is resolved once per frontmost application (and herdr agent-pane state) into a cached set of snippet IDs. Neither path may scan the snippet list or construct a `SnippetApplicationScope` per keystroke. The event tap's watchdog is a backstop only — the ordinary ways a tap dies arrive through the tap callback itself — so it runs every 5 seconds with matching tolerance.

`SmartInputLearningStore` holds roughly a megabyte of learned words once it reaches its 2,000-word limit, and every save rewrites all of it. Writes are debounced 30 seconds, encoded compactly without sorted keys, and performed off the lock so the event tap is never blocked behind a serialization. `AppDelegate` forces a synchronous flush on termination and before sleep.

## herdr panes

[herdr](https://herdr.dev) multiplexes shells and coding agents inside one terminal window, so the frontmost application alone says nothing about what receives keys. `HerdrPaneMonitor` fills that gap:

- It only acts while a terminal in `hostBundleIDs` is frontmost and its focused window title starts with `herdr`; `WindowActivityObserver` re-checks the title when windows change.
- It subscribes to `pane.focused`, `pane.agent_detected`, `pane.closed` and `pane.exited` on `~/.config/herdr/herdr.sock`, then reads `pane.list` once. The connection is held open on a background thread and reconnects with backoff while the window still says herdr. Nothing polls.
- The reduced state is published on the main queue as a `TerminalPaneFocus` (pane ID, agent name or `nil` for a shell).

Consumers:

- `LayoutAutomationEngine` keys its last-used layout memory by `TerminalPaneFocus.contextKey`, so every pane keeps its own layout. A shell pane gets U.S. whenever it gains focus; an agent pane gets the layout it was left on.
- `SmartInputService` keeps terminals security-excluded (a shell can prompt for a password), except the focused herdr pane when an agent runs in it: there smart RU/EN, Danish input and snippets apply as in any other text field.
- `AgentPromptTracker` follows the agent prompt from typed keys. When the prompt is known to be empty and the layout is not U.S., the key that types `/` on U.S. types `/`, U.S. is selected for the command, and the pane's layout comes back after the command word (space, Return, Control-C, or deleting back to empty). Any edit the tracker cannot follow — paste, history, word deletion, cursor keys, newlines, dictation, LayoutPilot's own replacements — makes the prompt unknown until the next submit, and an unknown prompt keeps the key's normal character. The key after herdr's `ctrl+b` prefix is treated as a herdr command.

The event tap only reads the cached pane snapshot; socket and accessibility work stay off the keystroke path.

## Extension points

The project is intentionally structured so later work can add:

- extra matching strategies for rules
- launch-at-login integration
- richer diagnostics and logging
- local LLM calls for assisted rule creation or classification

