# AI Agent Instructions for LayoutPilot

This repository contains critical macOS security-sensitive features. All AI agents, compilers, and automation scripts working on this repository must strictly adhere to the following rules:

---

## ⚠️ Critical Rule: Code Signing & Accessibility Permissions

LayoutPilot uses a low-level Event Tap via CoreGraphics (`CGEvent.tapCreate`) to capture and convert keyboard input for the smart layout feature. Under macOS security policies (TCC), this requires **Accessibility** permissions.

* **Mandatory Requirement**: All builds **MUST** preserve and apply valid code signing.
* **Why**: If the application is built without code signing (`CODE_SIGNING_ALLOWED: NO`) or with mismatched signatures, macOS TCC will invalidate its security tokens. This forces the user to manually toggle Accessibility permissions in System Settings every single time the application is rebuilt and run.
* **Implementation**:
  * In `project.yml`, the targets `LayoutPilot` and `LayoutPilotCore` must always have:
    ```yaml
    CODE_SIGNING_ALLOWED: YES
    CODE_SIGNING_REQUIRED: YES
    ```
  * The global `CODE_SIGN_IDENTITY` must be set to `"Apple Development: velizar.seleznev@gmail.com (VMQ79QRJFB)"` or a valid Apple Developer profile, and `DEVELOPMENT_TEAM` to `"KML84LMMXZ"`.
  * Do **NOT** override or disable these settings in the project file, target settings, or build scripts.

---

## 🛠 Project Lifecycle and Commands

Before proposing or performing any build:

1. **Regenerate Xcode Project**:
   Always run `xcodegen` to update the Xcode project configuration with code signing and target files:
   ```sh
   xcodegen
   ```

2. **Run Unit Tests**:
   Ensure all tests pass:
   ```sh
   xcodebuild -project LayoutPilot.xcodeproj -scheme LayoutPilot -derivedDataPath .build test
   ```

3. **Build & Run**:
   Use the custom build script:
   ```sh
   ./script/build_and_run.sh run
   ```

---

## ✅ Git Hygiene: Commit and Push Completed Changes

AI agents must not leave completed source changes floating in the working tree.

* After a coherent code or documentation change is implemented and verified, stage the relevant files and create a git commit before handing the task back.
* After creating a commit, push it to the current branch's configured remote before handing the task back. This is a personal project, so completed agent changes should be available on GitHub without a separate prompt.
* Keep commits focused and descriptive. Do not mix unrelated cleanup, generated artifacts, or user work into an implementation commit unless the user explicitly asks for that scope.
* Do not commit local build artifacts such as `.build/`, `LayoutPilot.xcodeproj/`, or generated `.dmg` files.
* If the working tree already contains unrelated user changes, preserve them. Commit only the files that belong to the current task, or clearly state why a clean commit cannot be made safely.
* If pushing is blocked because the remote has new work or the branch has no upstream, stop and report the exact blocker instead of force-pushing.
