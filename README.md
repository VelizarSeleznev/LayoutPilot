# LayoutPilot

LayoutPilot is a macOS utility project for:

- switching keyboard input sources automatically by frontmost application
- editing application-to-layout rules in a native macOS UI
- keeping room for future input automation and local LLM assistance

## Current shape

- `LayoutPilotCore` holds the reusable data models, persistence, input-source client, and automation engine.
- `LayoutPilot` is the native macOS app with a main window, settings scene, and menu bar extra.
- `Tests` covers the core configuration and persistence layer.

## Install

For normal use, download `LayoutPilot.dmg` from GitHub Releases, open it, drag
`LayoutPilot.app` to `Applications`, launch it, and grant Accessibility
permission in macOS when prompted.

For detailed DMG, source-build, signing, and permission steps, see
[docs/INSTALL.md](docs/INSTALL.md).

## Run

Generate the Xcode project, then run:

```sh
./script/build_and_run.sh
```

The run script builds with the configured development signature, copies the app to
`/Applications/LayoutPilot.app`, verifies the copied bundle signature, and launches
that installed app. Keeping the bundle at a stable `/Applications` path makes the
macOS Login Items and Accessibility permission state more predictable during local
development.

## Development & Code Signing

Since LayoutPilot uses a low-level Event Tap via CoreGraphics (`CGEvent.tapCreate`) for key interception, macOS requires **Accessibility** permissions, which in turn require valid code signing.

The project configuration in `project.yml` is preset with the original developer's credentials. If you are cloning and building this project:
1. Open `project.yml`.
2. Locate the `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` fields under `settings.base` (lines 10-11).
3. Replace them with your own Apple Developer credentials, or configure automatic signing in Xcode.
4. Run `xcodegen` and `./script/build_and_run.sh run` to build and launch with your signature.

## Notes

- The app seeds example rules for Word, Notion, and Terminal.
- The `LLM` settings block is a placeholder for later local model integration.
- Persistent configuration lives in `~/Library/Application Support/LayoutPilot/configuration.json`.
