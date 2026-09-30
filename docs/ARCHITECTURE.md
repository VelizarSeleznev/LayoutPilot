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

### Event tap lifecycle

The process holds at most one keyboard tap (`keyDown` + `flagsChanged`). `.tapDisabledByTimeout` and `.tapDisabledByUserInput` re-enable that same tap. It is recreated only when Claude launches (so it sits in front of Claude's Option listener; coalesced, at most once per 10 s) or when its Mach port dies, and teardown always disables the tap, removes and invalidates its run-loop source, and invalidates the Mach port before a new one is created. Removing only the run-loop source leaves an enabled tap nobody services in WindowServer's chain; on 2026-09-30 about 80 of those accumulated and every keystroke waited on them until the keyboard stopped working.

The watchdog runs on its own dispatch queue, not the tap thread. It re-enables a silently disabled tap, takes the tap out of the chain while a callback has been running for more than 1.5 s (and restores it once the callback returns), and counts the taps WindowServer holds for the process through `CGGetEventTapList`, logging `event_tap_count_anomaly` if that is not exactly one. The callback never calls Text Input Sources APIs: layout switches it asks for run on a serial `inputSourceQueue`.

`SmartInputLearningStore` holds roughly a megabyte of learned words once it reaches its 2,000-word limit, and every save rewrites all of it. Writes are debounced 30 seconds, encoded compactly without sorted keys, and performed off the lock so the event tap is never blocked behind a serialization. `AppDelegate` forces a synchronous flush on termination and before sleep.

## herdr panes

[herdr](https://herdr.dev) multiplexes shells and coding agents inside one terminal window, so the frontmost application alone says nothing about what receives keys. `HerdrPaneMonitor` fills that gap:

- It only acts while a terminal in `hostBundleIDs` is frontmost and its focused window carries the title herdr writes; `WindowActivityObserver` re-checks the title when windows or titles change. The title comes from herdr's `[ui] window_title` template in `~/.config/herdr/config.toml` (default `{hostname}: {workspace}`, re-read when the file changes): `HerdrWindowTitleMatcher` matches `{hostname}` exactly and the other tokens as any text. A template that cannot identify herdr — empty (herdr leaves the title alone), only free-form tokens, or a string form `HerdrConfig` does not parse — matches no window, so herdr panes then get no special handling and shell panes stay excluded.
- It subscribes to `pane.focused`, `pane.agent_detected`, `pane.closed` and `pane.exited` on `~/.config/herdr/herdr.sock`, then reads `pane.list` once. The connection is held open on a background thread and reconnects with backoff while the window is still herdr's. Nothing polls.
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

