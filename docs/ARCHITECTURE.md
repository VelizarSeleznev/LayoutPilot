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

## Extension points

The project is intentionally structured so later work can add:

- extra matching strategies for rules
- launch-at-login integration
- richer diagnostics and logging
- local LLM calls for assisted rule creation or classification

