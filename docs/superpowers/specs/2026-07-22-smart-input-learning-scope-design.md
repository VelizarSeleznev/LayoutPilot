# Smart Input Learning Scope

## Goal

Make Smart RU/EN learning global by default while preserving an optional per-application mode. LayoutPilot must continue collecting learning signals from every enabled application, explain the selected behavior in Settings, and allow the user to change scope without discarding learned data.

## User Experience

The Smart RU/EN section in Settings gains a `Learning scope` control with two choices:

- `Global` is the default for new and existing configurations. Corrections made in any application contribute to one shared learning profile and affect Smart RU/EN behavior everywhere.
- `Per app` keeps learned behavior separate for each application. A correction affects only the application where it was made.

The help text says: `Global learns from your corrections across every app. Per app keeps separate behavior for each application.`

The setting affects both kinds of local learning:

1. conversions the user repeatedly rejects with Undo or Backspace;
2. words the user repeatedly types and keeps without conversion.

This avoids a hidden hybrid where some learned decisions are global and others are application-specific.

## Configuration

Add a string-backed `SmartInputLearningScope` value with `global` and `perApplication` cases. `LayoutPilotConfiguration` stores the selected value, decodes a missing value as `global`, and includes `global` in its default configuration. `LayoutPilotStore` exposes a focused setter.

`LayoutPilotAppState` synchronizes the configured scope into `SmartInputService` at launch and whenever configuration changes. Changing the scope takes effect immediately and does not require restarting the application.

## Learning Data Model

The existing learning store already maintains aggregate counts and counts grouped by bundle identifier. This change keeps recording both forms for every learning event regardless of the active scope:

- the aggregate count represents the global profile;
- the bundle-specific count represents the per-application profile.

The selected scope changes only which count is consulted when deciding whether to suppress a conversion or accept a learned word. In `Global` mode, lookups omit the bundle identifier and use aggregate counts. In `Per app` mode, lookups include the active bundle identifier and use its isolated counts.

Because both count types continue to be recorded, switching scope is lossless and reversible. Existing learning files need no destructive migration.

## Runtime Data Flow

1. Smart Input receives a completed word or a rejected conversion together with the active application's bundle identifier.
2. The learning store records the aggregate count and, when available, the bundle-specific count.
3. Before a future conversion, `SmartInputService` resolves the lookup scope from configuration.
4. `Global` passes no bundle identifier to the lookup, selecting aggregate learning.
5. `Per app` passes the active bundle identifier, selecting application-specific learning.
6. The same lookup rule is used for rejected conversions and accepted learned words.

If an application has no usable bundle identifier, `Per app` mode falls back to aggregate lookup rather than silently disabling learning for that application.

## Components

### Models and Store

- Add `SmartInputLearningScope` to the core models.
- Add `smartInputLearningScope` to `LayoutPilotConfiguration` with backward-compatible decoding.
- Add `LayoutPilotStore.setSmartInputLearningScope(_:)`.

### Settings

- Add a two-option picker in the existing Smart RU/EN settings block.
- Use user-facing labels `Global` and `Per app`.
- Keep the explanatory copy visible below the control so the effect is understandable without a tooltip.

### Smart Input Service

- Store the active learning scope under the service's existing lock.
- Centralize lookup-bundle resolution so every learned decision follows the same scope.
- Continue passing the real bundle identifier to recording methods so both global and per-app histories remain current.

### Learning Store

- Extend accepted-word lookup to support the same optional bundle identifier semantics already used by conversion suppression.
- Preserve the existing aggregate and per-bundle persistence format.

## Failure Handling

- Unknown or missing configuration values decode to `global` through backward-compatible fallback behavior.
- Missing bundle identifiers in `Per app` mode use aggregate learning.
- Corrupt or absent learning files continue to start from an empty learning state using existing behavior.
- Scope changes never delete or rewrite prior learning history solely for migration.

## Testing and Verification

Unit tests cover:

- configurations without the new field decode to `global`;
- the default configuration uses `global`;
- the store setter persists both scope values;
- global rejected-conversion learning applies across different bundle identifiers;
- per-app rejected-conversion learning remains isolated;
- global accepted-word learning applies across applications;
- per-app accepted-word learning remains isolated;
- switching lookup scope reuses the same recorded data without loss;
- a missing bundle identifier in per-app mode falls back to aggregate learning.

Repository verification follows the required signed lifecycle:

1. Run `xcodegen`.
2. Run `xcodebuild -project LayoutPilot.xcodeproj -scheme LayoutPilot -derivedDataPath .build test`.
3. Run `./script/build_and_run.sh run`.
4. Verify the Settings control, immediate configuration synchronization, signed installed application, and representative global/per-app learning behavior.

Generated Xcode project files and build artifacts are not committed.

## Scope

This change does not add per-word rule editing, a learning-history browser, manual deletion of individual learned entries, cloud synchronization, or different scopes per learning category. It adds one understandable global/per-app choice over the existing local learning data.
