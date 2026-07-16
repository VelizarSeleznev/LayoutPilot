# Modular Interface and Snippets Design

Date: 2026-07-16
Status: Implemented

## Objective

Make LayoutPilot useful to people who need only one of its capabilities. Layout switching, Smart Danish, Smart RU/EN, and Snippets become independent modules instead of presenting layout automation as the product's default purpose.

The first feature expansion focuses on Snippets. It must support a useful single-snippet workflow with no organizational setup, while optionally providing folders and per-application availability for larger collections.

All user-facing copy remains English. The implementation remains a native SwiftUI macOS application and continues to respect the system appearance and accent color.

## Scope

This change covers:

- a module catalog replacing the current Home destination;
- first-run module selection;
- module-driven sidebar visibility and runtime gating;
- a redesigned Snippets list, creation sheet, and explicit editor flow;
- snippet display names;
- optional snippet folders;
- folder-level and snippet-level application availability;
- migration of existing configurations and snippets;
- validation and automated tests for the new model and behavior.

This version does not add dynamic variables, clipboard interpolation, cursor markers, cloud sync, sharing, usage statistics, or nested folders.

## Product Vocabulary

The interface distinguishes two concepts:

- **Added module:** The user has chosen the capability for their LayoutPilot workspace. Added modules appear in the sidebar and may run.
- **Active feature:** An added module's runtime behavior is currently on. Pausing a feature does not remove its configuration or its sidebar destination.

This distinction prevents a feature from disappearing immediately when its runtime switch is turned off. Removing a module happens only from My Modules. Removing it pauses the capability but preserves all of its configuration for later.

## Module Catalog and First Run

The current Home destination becomes **My Modules** and is always available. It presents four modules in this order:

1. Snippets
2. Smart Danish
3. Smart RU/EN
4. Layout Switching

Each card explains the user-visible outcome, reports `Added` or `Not Added`, and has one direct Add/Remove action. Snippets appears first because it is broadly useful and does not assume a multilingual typing problem. Cards use native materials, typography, switches or buttons, and the system accent color rather than a hard-coded brand pink.

On a new installation, My Modules opens as a first-run chooser with no module forced on. The user may select any combination, including only Snippets, then continue. Settings remains available even when no modules are selected.

Existing installations migrate with all currently exposed modules added so that an update does not unexpectedly hide controls or stop working features. Their existing runtime switches retain their values.

## Navigation

The visible sidebar is derived from the added-module set:

- My Modules is always visible.
- Snippets appears when the Snippets module is added.
- Smart Danish appears when the Smart Danish module is added.
- Smart RU/EN appears when the Smart RU/EN module is added.
- Applications, Websites, and Input Profiles appear as the Layout Switching group when that module is added.
- Settings is always visible at the bottom.

The module order is fixed in this version. User-customizable sidebar ordering is outside scope.

Removing the currently displayed module returns navigation to My Modules. Internal diagnostics and test destinations remain hidden as they are today.

## Runtime Gating

Module membership gates runtime behavior in addition to existing feature switches:

- snippets run only when the Snippets module is added and Text Snippets is active;
- Smart Danish runs only when its module is added and its existing runtime switch is active;
- Smart RU/EN runs only when its module is added and its existing runtime switch is active;
- application and website layout automation runs only when Layout Switching is added and Automatic Switching is active.

An unadded module cannot continue processing invisibly in the background. Adding it again restores the prior configuration and runtime-switch value.

## Snippet Data Model

### Snippet

`TextSnippet` gains:

- `name`: required human-readable label, not necessarily unique;
- `groupID`: optional folder identifier;
- `applicationScopeOverride`: optional application scope. `nil` means inherit from the folder, or all applications when ungrouped.

The existing fields remain:

- `id`;
- `trigger`;
- `replacement`;
- `isEnabled`.

Triggers remain globally unique in this version, including disabled snippets. This preserves the current deterministic lookup and avoids ambiguous expansion when scopes overlap. Trigger comparison is exact and case-sensitive, matching current runtime behavior.

### Folder

`TextSnippetGroup` contains:

- `id`;
- `name`;
- `applicationScope`.

Folders are flat and optional. A snippet with no `groupID` is shown as Ungrouped. Deleting a folder does not delete its snippets; they become ungrouped and retain no folder inheritance.

### Application scope

`SnippetApplicationScope` supports:

- all applications;
- only selected bundle identifiers;
- all except selected bundle identifiers.

An ungrouped snippet with no override works in all supported applications. A grouped snippet without an override inherits its folder's scope. A snippet override always replaces, rather than combines with, its folder scope so the result is explainable in the editor.

The existing hard-coded security exclusions for terminals and password managers continue to take precedence over all snippet scope settings.

## Snippets Main View

The page retains a native two-pane layout inside the application detail area:

- the left pane contains search, filter controls, and the snippet list;
- the right pane contains the selected snippet editor or an empty state.

Folders appear as list sections and as a filter, not as another permanent column. This avoids turning the existing application sidebar plus Snippets page into a four-column interface.

The toolbar contains:

- an Active switch for the module's runtime state;
- `New Snippet` as the primary action;
- a secondary menu with `New Folder` and folder-management actions.

Each list row shows the human-readable name, trigger, a one-line replacement preview, and a paused indicator when disabled. Search matches name, trigger, replacement, and folder name. Filters cover All Snippets, Ungrouped, and individual folders.

When no snippets exist, the page presents one clear `Create Snippet` action and explains that folders are optional. When search or filtering has no results, the empty state offers to clear the active query or filter rather than suggesting creation of a duplicate item.

## Creating One Snippet

`New Snippet` opens a native SwiftUI sheet. No placeholder snippet is written to the store.

The immediately visible fields are:

1. Name
2. Trigger
3. Text

An optional `Organization & Apps` disclosure contains:

- Folder, defaulting to None;
- application availability, defaulting to Inherit when a folder is selected and All Applications when ungrouped.

The footer contains Cancel and Create. Create is disabled until required fields are non-empty after trimming. A duplicate trigger produces a direct inline error and leaves the sheet open. Pressing Escape cancels without creating data. A successful Create selects the new snippet and opens it in the editor.

Creating a folder is never required before creating the first snippet.

## Editing

Selecting a snippet loads a local draft. Changes do not write through on every keystroke.

The editor contains:

- Name;
- Trigger;
- Text;
- Active switch for the individual snippet;
- Folder;
- application availability, with inherited scope stated explicitly;
- Save Changes and Cancel buttons;
- Delete Snippet as a secondary destructive action.

Save Changes uses the same validation as creation. Cancel restores the stored value. Switching selection with unsaved changes presents Save, Discard, and Cancel choices. Closing the window with an unsaved draft uses the same protection.

Deleting a snippet requires confirmation and then selects the next visible row. Deleting a folder requires confirmation that its snippets will become ungrouped.

## Store and Service Boundaries

`LayoutPilotStore` remains the source of truth for persisted configuration. Snippet mutations move from silent normalization to validated operations that return a concrete success or validation failure. Views keep drafts locally and commit only through these operations.

Snippet availability is resolved by a small core-layer policy function that receives a snippet, the folder collection, and the active bundle identifier. `SmartInputService` consumes only the resolved eligible snippets. It does not own UI selection, folder editing, or validation logic.

A single module registry defines module identity, title, icon, sidebar destinations, and runtime gate. My Modules and Sidebar both consume this registry so their visibility rules cannot drift apart.

## Configuration Migration

Configurations without module metadata are treated as existing installations and migrate with all four modules added. New default configurations explicitly record that module selection has not been completed.

Existing snippets decode as follows:

- `name` defaults to the existing trigger;
- `groupID` is `nil`;
- `applicationScopeOverride` is `nil`;
- their existing trigger, replacement, enabled state, and identifier are preserved.

Missing folder references caused by manually edited or damaged configuration are normalized to Ungrouped. Unknown bundle identifiers remain stored so an application that is temporarily absent does not disappear from a scope rule.

## Error Handling

- Empty name, trigger, or text is explained next to the affected field.
- Duplicate triggers identify the existing snippet by name and offer no destructive automatic merge.
- Failed persistence keeps the user's draft and surfaces the store error in the sheet or editor.
- A missing inherited folder falls back to All Applications and is normalized to Ungrouped on the next successful save.
- If Accessibility permission is unavailable, module configuration remains editable, but an inline message explains that expansion cannot run and links to the existing permission action.
- Security-excluded applications are not offered as selectable scope entries and always remain excluded at runtime.

## Accessibility and Keyboard Behavior

- All icon-only controls have accessibility labels and help text.
- Add/Remove, Active/Paused, inherited scope, and validation are communicated in text rather than color alone.
- Tab order follows Name, Trigger, Text, optional settings, then the primary action.
- Command-N opens New Snippet while the Snippets module is visible.
- Command-S saves a valid edited draft.
- Escape cancels the creation sheet and participates in unsaved-change protection.
- Native focus rings and system accent color are preserved.

## Verification

Automated tests cover:

- decoding existing configurations with all modules added;
- new-install module selection state;
- sidebar destinations for every added-module combination;
- effective runtime gates combining module membership with feature switches;
- migration of existing snippets to a trigger-derived name and no folder;
- creation of an ungrouped snippet without application configuration;
- empty-field and duplicate-trigger validation;
- folder creation, rename, and deletion without snippet deletion;
- folder scope inheritance and snippet override resolution;
- all, only-selected, and all-except application scopes;
- precedence of hard-coded security exclusions;
- snippet search and filter policy;
- preservation of drafts after validation or persistence failure.

Manual verification covers:

- first run with only Snippets selected;
- adding and removing each module from My Modules;
- creating the first snippet with only Name, Trigger, and Text;
- creating and assigning an optional folder;
- limiting a folder to selected applications and overriding one snippet;
- Save, Cancel, selection-change protection, and deletion confirmation;
- keyboard navigation, Command-N, Command-S, Escape, dark mode, and system accent colors;
- actual expansion in an allowed application and suppression in a disallowed or security-excluded application.

Repository verification follows the required lifecycle:

1. run `xcodegen`;
2. run `xcodebuild -project LayoutPilot.xcodeproj -scheme LayoutPilot -derivedDataPath .build test`;
3. run `./script/build_and_run.sh run`;
4. visually inspect the native SwiftUI interface and exercise snippet expansion in a real application.

Code signing settings in `project.yml` remain unchanged and enabled for both targets.
