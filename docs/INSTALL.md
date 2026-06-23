# Installing LayoutPilot

LayoutPilot is a macOS utility that watches keyboard input with a CoreGraphics
event tap. macOS requires Accessibility permission for that feature, and the app
must stay code-signed so the permission remains stable between launches.

## Option 1: Install from a DMG

Use this path if you just want to run LayoutPilot.

1. Download `LayoutPilot.dmg` from the project's GitHub Releases page.
2. Open the DMG.
3. Drag `LayoutPilot.app` into the `Applications` shortcut.
4. Eject the DMG.
5. Launch LayoutPilot from `/Applications`.
6. Grant Accessibility permission when macOS asks.

If macOS does not show the prompt:

1. Open **System Settings**.
2. Go to **Privacy & Security** -> **Accessibility**.
3. Enable `LayoutPilot`.
4. Quit and reopen LayoutPilot.

If macOS says the app cannot be opened because the developer cannot be verified,
use **right-click** -> **Open** once, then confirm. This can happen for
development-signed builds. A public release should be signed with a Developer ID
certificate and notarized before sharing broadly.

## Option 2: Build from source

Use this path if you are a developer or want to run your own signed build.

### Requirements

- macOS 14 or newer.
- Xcode installed.
- Xcode command-line tools selected with `xcode-select`.
- `xcodegen` installed and available on `PATH`.
- A valid Apple code-signing identity. A paid Developer ID is not required for
  local development, but a local Apple Development identity keeps Accessibility
  permissions stable.

### Configure signing

The repository's `project.yml` contains the original developer's signing values:

```yaml
CODE_SIGN_IDENTITY: "Apple Development: velizar.seleznev@gmail.com (VMQ79QRJFB)"
DEVELOPMENT_TEAM: "KML84LMMXZ"
```

If you are building on another Apple Developer account, replace those values with
your own identity and team ID before building.

### Build and run locally

From the repository root:

```sh
xcodegen
xcodebuild -project LayoutPilot.xcodeproj -scheme LayoutPilot -derivedDataPath .build test
./script/build_and_run.sh run
```

The run script builds LayoutPilot, copies it to `/Applications/LayoutPilot.app`,
verifies the copied app signature, and launches that installed copy. Keeping the
app at the same `/Applications` path helps macOS remember Accessibility
permission for the same signed app.

### Create a local DMG

```sh
./script/package_dmg.sh
```

This creates `LayoutPilot.dmg` in the repository root. If the machine has a
`Developer ID Application` certificate, the script can use it for distribution:

```sh
REQUIRED_DISTRIBUTION_SIGNING=1 ./script/package_dmg.sh
```

Without a Developer ID certificate, the DMG is suitable for local testing but may
trigger Gatekeeper warnings on another Mac.

## Accessibility troubleshooting

If smart input or layout switching does not work:

1. Confirm LayoutPilot is running from `/Applications/LayoutPilot.app`.
2. Open **System Settings** -> **Privacy & Security** -> **Accessibility**.
3. Toggle `LayoutPilot` off and on.
4. Quit and reopen LayoutPilot.

If permissions still do not stick, rebuild with valid code signing. Do not set
`CODE_SIGNING_ALLOWED=NO`; that breaks macOS TCC identity tracking and can force
Accessibility permission to be re-granted after every build.
