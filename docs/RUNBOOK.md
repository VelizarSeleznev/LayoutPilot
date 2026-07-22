# Runbook

## Build and run

```sh
./script/build_and_run.sh
```

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
