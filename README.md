# LayoutPilot

LayoutPilot is a macOS utility project for:

- switching keyboard input sources automatically by frontmost application
- editing application-to-layout rules in a native macOS UI
- keeping room for future input automation and local LLM assistance

## Current shape

- `LayoutPilotCore` holds the reusable data models, persistence, input-source client, and automation engine.
- `LayoutPilot` is the native macOS app with a main window, settings scene, and menu bar extra.
- `Tests` covers the core configuration and persistence layer.

## Run

Generate the Xcode project, then run:

```sh
./script/build_and_run.sh
```

## Notes

- The app seeds example rules for Word, Notion, and Terminal.
- The `LLM` settings block is a placeholder for later local model integration.
- Persistent configuration lives in `~/Library/Application Support/LayoutPilot/configuration.json`.

