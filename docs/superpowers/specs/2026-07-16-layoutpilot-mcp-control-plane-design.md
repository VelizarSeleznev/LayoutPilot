# LayoutPilot MCP Control Plane Design

**Date:** 2026-07-16
**Status:** Approved for implementation

## Goal

Let an MCP client inspect and configure all supported LayoutPilot features without opening the app UI. The MCP server must work when LayoutPilot is not running, must keep a running app synchronized, and must not allow the app and MCP process to overwrite each other's changes.

## Product Contract

The user can describe a LayoutPilot change to an MCP-capable assistant and have it applied directly. The UI remains available but is not required for configuration.

The first release covers the complete current configuration surface:

- feature modules;
- snippets, snippet folders, application availability, and expansion timing;
- Smart Danish and Smart RU/EN settings and application lists;
- spelling autocorrect;
- application rules;
- website rules;
- input profiles;
- global automation, menu bar, and launch-at-login settings.

The server does not expose an arbitrary JSON write tool. Every mutation uses a typed domain operation and existing validation rules.

## Architecture

### Shared Configuration Repository

Add `LayoutPilotConfigurationRepository` to `LayoutPilotCore`. It becomes the only production path that writes `configuration.json`.

Each mutation is a transaction:

1. acquire an exclusive lock on a stable `configuration.lock` file;
2. read and decode the latest configuration from disk;
3. normalize and validate the current data;
4. apply one typed mutation;
5. validate the result;
6. preserve the previous valid configuration as `configuration.backup.json`;
7. encode to a temporary file, flush it, and atomically replace `configuration.json`;
8. release the lock and return the committed configuration.

Reads also pass through the repository and never rely on a stale MCP-process snapshot. The lock file is stable across atomic configuration-file replacement.

If the primary configuration cannot be decoded but the backup is valid, the repository restores the backup under the same lock and reports that recovery in its result. If both files are invalid, reads and mutations fail with `configuration_corrupt` and neither file is overwritten.

`LayoutPilotStore` keeps its observable in-memory configuration for SwiftUI but delegates persistence to the repository. Its mutation methods transact against the latest disk value rather than writing a value derived from a potentially stale snapshot. Direct full-configuration replacement remains available only as an explicit repository operation for Reset and tests.

### Live Reload

When LayoutPilot is running, the store watches the containing configuration directory so atomic file replacement is observable. External changes are debounced, decoded, normalized, and published to SwiftUI without writing them back again. The existing change handler then refreshes runtime services, rules, snippets, and menu state.

Self-originated writes are ignored when their loaded configuration equals the current state. Invalid external data does not replace the live configuration; the store reports the error and keeps the last valid state.

### MCP Executable

Add a signed `LayoutPilotMCP` command-line target linked to `LayoutPilotCore` and the official Swift MCP SDK, pinned to version `0.12.1` so a pre-1.0 package update cannot silently change the server API.

The executable is embedded at:

`/Applications/LayoutPilot.app/Contents/MacOS/LayoutPilotMCP`

It uses the standard stdio transport. Standard output contains MCP protocol messages only; diagnostic logging goes to standard error and the local audit log.

The installed Codex configuration contains:

```toml
[mcp_servers.layoutpilot]
command = "/Applications/LayoutPilot.app/Contents/MacOS/LayoutPilotMCP"
```

The MCP process is launched on demand by the client. LayoutPilot itself does not need to be running and no network port is opened.

## Tool Surface

Tool names use the `layoutpilot_` prefix and return structured JSON plus a concise human-readable summary.

### State and Settings

- `layoutpilot_get_state`: return configuration, installed app version, whether the app is running, and the most recent configuration error.
- `layoutpilot_update_settings`: patch supported global, Smart Danish, Smart RU/EN, spelling, snippet, and menu settings. Omitted fields remain unchanged.
- `layoutpilot_set_modules`: replace the added-module set with validated module identifiers.

`layoutpilot_update_settings` includes snippet expansion timing but not entity collections such as snippets or rules.

### Snippets

- `layoutpilot_list_snippets`
- `layoutpilot_create_snippet`
- `layoutpilot_update_snippet`
- `layoutpilot_delete_snippet`
- `layoutpilot_list_snippet_folders`
- `layoutpilot_create_snippet_folder`
- `layoutpilot_update_snippet_folder`
- `layoutpilot_delete_snippet_folder`

Create accepts name, trigger, replacement, enabled state, optional folder ID, and optional application-scope override. Update requires an exact snippet ID and changes only supplied fields. Delete requires an exact ID and returns the deleted entity summary. Folder deletion preserves snippets as ungrouped, matching the UI.

### Input Profiles and Rules

- `layoutpilot_list_input_profiles`
- `layoutpilot_upsert_input_profile`
- `layoutpilot_delete_input_profile`
- `layoutpilot_list_application_rules`
- `layoutpilot_upsert_application_rule`
- `layoutpilot_delete_application_rule`
- `layoutpilot_list_website_rules`
- `layoutpilot_upsert_website_rule`
- `layoutpilot_delete_website_rule`

Upsert operations accept an optional ID. Without an ID they create an entity; with an ID they update exactly that entity. References to missing profiles or folders fail validation instead of being silently removed. Empty or malformed application bundle IDs fail validation, while valid bundle IDs do not require the application to be currently installed.

## Validation and Errors

The repository and MCP handlers share domain validation from `LayoutPilotCore`.

Expected failures return MCP tool errors with stable error codes and actionable messages, including:

- `not_found`
- `duplicate_trigger`
- `invalid_reference`
- `invalid_scope`
- `invalid_setting`
- `configuration_corrupt`
- `persistence_failed`
- `system_approval_required`

Mutations are all-or-nothing. A failed mutation leaves both the configuration file and the in-memory app state unchanged.

For launch at login, the desired configuration value is persisted and the shared `LaunchAtLoginService` reports the actual macOS state. If macOS requires approval, the tool succeeds with status `requires_approval` and explains the remaining system action. If the system service call fails, the response reports `system_error`, the desired persisted value, and the unchanged actual service state. The configuration transaction is not rolled back because the external macOS service operation cannot be part of the file transaction.

## Security and Privacy

- The server is local stdio only.
- It exposes no shell execution, arbitrary file access, or arbitrary configuration JSON mutation.
- Tool schemas use enums for module names, modes, and rule targets.
- Destructive operations require exact stable IDs.
- Security-excluded application rules for snippets remain enforced by the runtime.
- Existing code signing requirements remain enabled for the app, core framework, and MCP executable.
- MCP audit entries contain timestamp, tool name, entity IDs, changed field names, and result. They do not contain snippet replacement bodies or other free-form user text.

The audit log is stored as `mcp-audit.jsonl` in the LayoutPilot application-support directory and uses bounded rotation.

## Installation and Updates

`project.yml` defines and signs the MCP target, embeds its executable in the app bundle, and includes it in the main scheme. The build-and-run script installs the complete signed bundle.

A repository installer command uses `codex mcp remove layoutpilot` when necessary and `codex mcp add layoutpilot -- <installed executable>` to replace only LayoutPilot's registered MCP entry after explicit invocation. It does not parse or rewrite unrelated Codex settings. Development verification invokes this installer for the current user and confirms the MCP server through a real initialize, tools/list, and tool-call sequence.

Because the configured path is inside `/Applications/LayoutPilot.app`, later app updates replace the MCP executable without requiring a new Codex path.

## Data Flow

```text
Codex
  -> stdio MCP request
  -> LayoutPilotMCP typed handler
  -> LayoutPilotConfigurationRepository transaction
  -> lock + validate + backup + atomic write
  -> structured MCP result

configuration directory change
  -> running LayoutPilot watcher
  -> observable store reload
  -> runtime service synchronization
```

If LayoutPilot is not running, the transaction still completes. The next launch reads the committed configuration normally.

## Testing

### Repository

- atomic read-modify-write;
- backup contains the previous valid configuration;
- corrupt current configuration is restored from a valid backup;
- corrupt current and backup files fail without overwriting either file;
- two repository instances performing concurrent mutations do not lose updates;
- directory watcher reloads an external atomic replacement exactly once;
- self-writes do not cause persistence loops.

### MCP Tools

- initialize and tools/list over stdio;
- every list, create, update, upsert, and delete operation;
- partial settings patches preserve omitted fields;
- exact-ID and reference validation;
- validation errors use stable codes;
- audit records omit free-form replacement text;
- tools operate when LayoutPilot is not running.

### Integration

- a real MCP call creates a snippet while the app is closed;
- the app launches and uses that snippet;
- a real MCP call changes the configuration while the app is running and the UI/runtime reload;
- simultaneous UI and MCP mutations preserve both changes;
- launch-at-login reports the actual macOS service state;
- the installed app, core framework, and MCP executable pass strict code-sign verification;
- the Codex MCP entry launches the installed executable and can perform a read and a reversible write.

## Delivery

Implementation is split into focused commits:

1. shared transactional repository and live reload;
2. MCP target and typed tools;
3. installer, Codex registration, integration verification, and documentation.

Each commit preserves a passing test suite and valid code signing.
