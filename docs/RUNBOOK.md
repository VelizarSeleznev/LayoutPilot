# Runbook

## Build and run

```sh
./script/build_and_run.sh
```

This builds `Release`. The installed app runs all day holding an event tap, and a `-Onone`
build of it measurably costs battery, so `Debug` is opt-in:

```sh
LAYOUTPILOT_CONFIGURATION=Debug ./script/build_and_run.sh
```

To tell them apart in an installed bundle, look in `Contents/MacOS`: a `Debug` build carries
`LayoutPilot.debug.dylib` and `__preview.dylib` alongside the main binary.

User-facing install instructions live in [INSTALL.md](INSTALL.md).

## Project artifacts

- Project file: `LayoutPilot.xcodeproj`
- Build script: `script/build_and_run.sh`
- Codex Run action: `.codex/environments/environment.toml`

Persistent state is stored at:

`~/Library/Application Support/LayoutPilot/configuration.json`

## Git workflow

- Keep completed work committed. After implementing and verifying a coherent change, stage the relevant files and create a focused commit before ending the task.
- Do not commit generated local artifacts such as `.build/`, `LayoutPilot.xcodeproj/`, or generated `.dmg` files.
- If unrelated user changes are already present, leave them intact and commit only the files that belong to the current task.

## Releasing Updates

The production feed is served from GitHub Pages at
`https://velizarseleznev.github.io/LayoutPilot/appcast.xml`. The repository's
Pages source must remain set to the `/docs` directory on the `main` branch.

Installed builds check this feed every six hours. With automatic updates
enabled, Sparkle downloads a signed update in the background and LayoutPilot
restarts briefly to install it. Users can disable this or trigger a manual
check from Settings.

To publish a new update for LayoutPilot:

1. Run the release automation script:
   ```sh
   ./script/release.py
   ```
2. Confirm the version number, build number, and enter release notes. The script will:
   - Update `project.yml` with the new version.
   - Run tests to ensure stability.
   - Build a Release `LayoutPilot.dmg`.
   - Sign the DMG with Sparkle's Ed25519 key.
   - Prepend the new update item block in `docs/appcast.xml`.
   - Commit and push changes to git.
   - Create a GitHub Release and upload `LayoutPilot.dmg`.

For a DMG intended for other people, build with a `Developer ID Application`
certificate and notarize the app before broad distribution. A development-signed
DMG is useful for local testing, but other Macs may show Gatekeeper warnings.

---

## Current scope

- automatic input-source switching by frontmost bundle ID
- UI for app rules and input profiles
- placeholder LLM settings for future expansion

### External global dictation (2026-09-28)

LayoutPilot no longer auto-launches Vibe Read or forwards Fn/Option gestures to
its control socket. With Instant Globe switching enabled, short Fn taps still
switch the input source on release. Long Fn holds do not switch the source;
Fn events pass through so the user's global dictation app can observe them.
Double Option is also passed through. Another app may still bind that gesture.

The gesture regression tests pass. The full 152-test run had one failure in
`testBilingualConversionCorrectsDoubleInitialUppercaseAfterTranslation`
(nil versus `Что`), outside the changed gesture path. Microphone transcription
and insertion through ChatGPT require a live user check.

### Direct Control dictation (2026-09-28)

The delayed Fn-to-F18 experiment was reverted after the user reported that
holding Fn did nothing. ChatGPT hold-to-dictate is now configured as
`LeftControl` in `~/.codex/keybindings.json`. Restart ChatGPT to reload its
native shortcut. LayoutPilot retains short Fn layout switching and does not
launch Vibe Read or synthesize dictation keys. The live Control recording path
needs verification after ChatGPT restarts.
