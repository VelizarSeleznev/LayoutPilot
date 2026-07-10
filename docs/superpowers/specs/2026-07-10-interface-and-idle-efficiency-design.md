# LayoutPilot Interface and Idle-Efficiency Design

Date: 2026-07-10
Status: Approved for implementation

## Objective

Make LayoutPilot feel like a focused macOS utility instead of a developer dashboard. The menu bar should follow the interaction language of macOS Battery and Wi-Fi controls, and the main window should expose the useful configuration without duplicating navigation. At the same time, the background engine must stop waking the app four times per second when nothing has changed.

All user-facing copy remains English. Existing diagnostics and test code stays available in the codebase but disappears from normal navigation and the menu bar.

## Scope

This change covers:

- the menu bar popover;
- the main window navigation and Home page;
- Settings as a section of the main window;
- hiding AX Inspector, Selection Inspector, Diagnostics, and LLM Chat (Test) from normal UI;
- retaining the last external app and website context while LayoutPilot is frontmost;
- useful recent-app controls on Home;
- reducing background CPU and wakeups caused by broad polling;
- tests for navigation visibility, context retention, and refresh scheduling.

The underlying application, website, profile, snippet, inspector, diagnostics, and chat implementations are not deleted. This pass does not redesign the data model or add new user features.

## Design Principles

1. Use native macOS hierarchy and controls. Avoid decorative cards, glowing status dots, and animation in idle.
2. A control must look like what it does. Selection, on/off state, context, and navigation use distinct treatments.
3. Keep rare choices compact. Layout profiles belong in dropdowns because they are configured infrequently and the list may grow.
4. Do not duplicate the sidebar on Home. The large content area should provide context and recent work instead.
5. Never let LayoutPilot replace the external context it is supposed to configure.

## Information Architecture

The visible sidebar contains these sections:

- Home
- Applications
- Websites
- Profiles
- Snippets
- Settings

The sidebar groups Applications and Websites under Rules, and Profiles and Snippets under Tools. Settings sits at the bottom as a first-class destination.

`Diagnostics` and `LLM Chat (Test)` remain addressable internally but are excluded from the user-facing section list. The two inspector controllers remain compiled but have no normal menu-bar entry.

The existing `Command-,` shortcut no longer opens a separate settings window. It activates the main LayoutPilot window and selects Settings. The menu bar Settings action does the same.

## Menu Bar

### Structure

The popover uses a compact vertical hierarchy:

1. `LayoutPilot` header with one global Automatic Switching switch.
2. Active external application identity.
3. `App Layout` dropdown.
4. `Smart RU/EN` and `Smart Danish` rows.
5. Optional current website identity and `Site Layout` dropdown.
6. Plain action rows: Open LayoutPilot, Settings, and Quit LayoutPilot.

There is no button strip at the bottom and no activity indicator.

### Interaction semantics

- The global Automatic Switching control is a switch because it enables or disables the whole automation engine.
- `App Layout` is a compact dropdown containing `No Override`, `Last Used`, and all configured profiles.
- Smart RU/EN and Smart Danish are independent toggle rows. Enabled rows use the accent-colored circular icon; disabled rows use a neutral icon. Their text also reports `On` or `Off`.
- The current website domain is non-interactive context, not a selectable row.
- `Site Layout` is a compact dropdown. Its first option, `Use App Layout`, removes the website override; remaining options are configured profiles.
- Open, Settings, and Quit are plain action rows with line icons. They never use accent circles, checkmarks, or selected backgrounds.

### Website visibility

The website block appears only when a supported browser is the active external application and a domain is available. Smart Input controls remain visible in browsers whether or not a website is detected.

## Main Window

### Home header

Home uses a restrained title, a short readiness sentence, and the global Automatic Switching control. It does not show engine statistics, a pipeline diagram, or an animated status marker.

### Last Active Context

The left column shows the last external application used before LayoutPilot became frontmost. It contains:

- the external app icon and name;
- App Layout dropdown;
- Smart RU/EN and Smart Danish toggle rows;
- the last website domain and Site Layout dropdown when applicable.

LayoutPilot, unknown processes, and transient internal panels cannot replace this context. The value remains stable while the main window is active and updates when the user returns from another external app.

### Recent Applications

The right column replaces the redundant Quick Access list with up to four recent external applications. Each row provides:

- app icon and name;
- App Layout dropdown;
- compact Smart RU/EN and Smart Danish toggle icons.

Recent applications exclude LayoutPilot and unknown contexts, are ordered most-recent-first, and contain no duplicates. Editing a row updates the same store used by the Applications page and menu bar.

### Other sections

Applications, Websites, Profiles, and Snippets retain their existing capabilities. Their pages use consistent navigation titles, spacing, section grouping, and native controls; developer-facing explanatory copy and dashboard decoration should not be introduced. Settings reuses the existing settings controls inside the main detail area.

## Context and State Flow

`LayoutPilotAppState` owns the selected main-window section and the last external context exposed to UI. The automation engine continues to own application and website detection.

When an external application activates:

1. the engine resolves its app identity;
2. the engine evaluates the app rule;
3. browser context is evaluated only when relevant;
4. the stable last-external context and recent-app list update;
5. SwiftUI state publishes only if a visible value changed.

When LayoutPilot activates, the engine may note that the app is frontmost but must not publish LayoutPilot as the configurable context or insert it into recent apps.

All menu bar, Home, and Applications edits write through existing `LayoutPilotStore` methods, then request a targeted engine reevaluation. There is one source of truth for rules and Smart Input allowlists.

## Idle-Efficiency Design

### Confirmed cause

Profiling the installed Debug build showed approximately 0.4–0.6% CPU while idle and about ten minutes of accumulated CPU time over a 24-hour process lifetime. The dominant recurring stack was `LayoutAutomationEngine.refreshNow`, scheduled every 250 ms. Each pass queried the frontmost context, Spotlight through Accessibility and the window list, and the current input source. When a supported browser is frontmost, the same broad pass can also execute AppleScript URL retrieval up to four times per second.

The Event Tap run loop and its one-second watchdog were nearly idle in the sample and are not the primary target.

### Replacement scheduling

Remove the unconditional 250 ms refresh timer. Refresh application state from concrete events:

- `NSWorkspace.didActivateApplicationNotification`;
- input-source selection notifications;
- configuration changes;
- menu bar presentation and main-window activation when a fresh display value is required;
- existing Smart Input handling for known keyboard-driven transitions such as Spotlight and browser new-tab shortcuts.

Website URL monitoring is conditional:

- it runs only while a supported browser is the last active external application;
- its repeating monitor runs only when at least one website rule is enabled;
- it refreshes immediately on browser activation and relevant known shortcuts;
- while required, its fallback interval is 2 seconds with 500 ms leeway to catch mouse-driven tab or navigation changes;
- presenting the menu bar or Home requests a one-shot domain refresh but does not start a repeating monitor solely for display;
- URL retrieval happens away from the main actor, and identical domains do not republish observable state.

Spotlight detection must not enumerate every visible window four times per second. The existing Command-Space keyboard path is the primary fast path. A mouse click in the menu-bar region may schedule one delayed, one-shot Spotlight probe so opening Spotlight by clicking its icon remains supported without an idle timer.

### Performance acceptance criteria

- There is no repeating 250 ms automation timer in steady state.
- With a non-browser external app idle for 60 seconds, LayoutPilot performs no broad app/Spotlight refresh loop and averages at or below 0.1% CPU in the installed Debug build on the development machine.
- With a supported browser frontmost, URL checks occur only under the conditional browser monitor and never at 4 Hz.
- A mouse-driven website change with an enabled rule is applied within 2.5 seconds.
- Opening the menu bar or main window shows correct app state without visible delay.
- App switching and keyboard-layout switching remain functionally correct.

## Error and Empty States

- If there is no retained external app, Home says `Switch to another app to begin` and hides app-specific controls.
- If the active browser domain cannot be read, the website block is omitted; app controls remain usable.
- If a selected profile was deleted, the dropdown falls back to `No Override` or `Use App Layout` as appropriate and the existing store error is surfaced in the relevant editor page.
- Automation errors use a concise inline message on Home. They do not create persistent animation or polling.
- Missing Accessibility or Automation permission should provide one direct explanation and a path to the relevant System Settings pane.

## Accessibility and Visual Behavior

- All icon-only compact controls have accessibility labels and values.
- Accent color is never the sole indicator of an on/off value; text exposes `On` or `Off`.
- Keyboard focus and native control behavior are preserved.
- The UI respects system appearance and accent color rather than hard-coding pink.
- Reduced Motion requires no special fallback because the approved design contains no ambient animation.

## Verification

Automated coverage should verify:

- the visible sidebar section list excludes Chat and Diagnostics and includes Settings;
- LayoutPilot and unknown contexts never enter last-external or recent-app state;
- recent apps are ordered, deduplicated, and limited to four;
- app and website dropdown selections map to existing rule targets correctly;
- `Use App Layout` deletes or disables the website override;
- Settings actions route to the main window Settings section;
- event-driven refresh scheduling replaces the unconditional timer;
- conditional website monitoring starts and stops for the correct states;
- unchanged snapshots do not trigger observable republishing.

Repository verification follows the required lifecycle:

1. run `xcodegen`;
2. run `xcodebuild -project LayoutPilot.xcodeproj -scheme LayoutPilot -derivedDataPath .build test`;
3. run `./script/build_and_run.sh run`;
4. measure the rebuilt installed process at idle and while a browser is frontmost;
5. visually inspect the menu bar, Home, sidebar, and Settings routing.

Code signing settings in `project.yml` remain unchanged and enabled for both targets.
