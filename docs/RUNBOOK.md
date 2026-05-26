# Runbook

## Build and run

```sh
./script/build_and_run.sh
```

## Project artifacts

- Project file: `LayoutPilot.xcodeproj`
- Build script: `script/build_and_run.sh`
- Codex Run action: `.codex/environments/environment.toml`

## Configuration

Persistent state is stored at:

`~/Library/Application Support/LayoutPilot/configuration.json`

## Current scope

- automatic input-source switching by frontmost bundle ID
- UI for app rules and input profiles
- placeholder LLM settings for future expansion

