#!/usr/bin/env python3
import sys
import os
import re
import subprocess
import time

def run_command(args, cwd=None):
    print(f"Running: {' '.join(args)}")
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error executing command: {' '.join(args)}")
        print(f"Stdout:\n{result.stdout}")
        print(f"Stderr:\n{result.stderr}")
        sys.exit(result.returncode)
    return result.stdout

def main():
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    project_yml_path = os.path.join(project_dir, "project.yml")
    appcast_path = os.path.join(project_dir, "docs", "appcast.xml")
    
    if not os.path.exists(project_yml_path):
        print(f"Error: project.yml not found at {project_yml_path}")
        sys.exit(1)

    # 1. Read current version and build number
    with open(project_yml_path, "r") as f:
        project_yml = f.read()

    short_version_match = re.search(r'CFBundleShortVersionString:\s*"([^"]+)"', project_yml)
    version_match = re.search(r'CFBundleVersion:\s*"([^"]+)"', project_yml)

    current_version = short_version_match.group(1) if short_version_match else "1.0"
    current_build = version_match.group(1) if version_match else "1"

    print(f"Current version: {current_version}")
    print(f"Current build: {current_build}")

    # Suggest next version (increment patch or minor)
    suggested_version = current_version
    try:
        parts = current_version.split(".")
        if len(parts) >= 2:
            parts[-1] = str(int(parts[-1]) + 1)
            suggested_version = ".".join(parts)
    except ValueError:
        pass

    try:
        suggested_build = str(int(current_build) + 1)
    except ValueError:
        suggested_build = "1"

    # Prompt user
    new_version = input(f"Enter new version [{suggested_version}]: ").strip() or suggested_version
    new_build = input(f"Enter new build number [{suggested_build}]: ").strip() or suggested_build
    release_notes = input("Enter release notes/title for this update: ").strip() or "Bug fixes and improvements"

    # 2. Update project.yml
    print("=== Step 1: Updating project.yml ===")
    project_yml = re.sub(r'CFBundleShortVersionString:\s*"[^"]+"', f'CFBundleShortVersionString: "{new_version}"', project_yml)
    project_yml = re.sub(r'CFBundleVersion:\s*"[^"]+"', f'CFBundleVersion: "{new_build}"', project_yml)
    
    with open(project_yml_path, "w") as f:
        f.write(project_yml)

    # 3. Regenerate project
    print("=== Step 2: Regenerating Xcode project with xcodegen ===")
    run_command(["xcodegen"], cwd=project_dir)

    # 4. Run tests
    print("=== Step 3: Running unit tests ===")
    test_args = [
        "xcodebuild",
        "-project", "LayoutPilot.xcodeproj",
        "-scheme", "LayoutPilot",
        "-derivedDataPath", ".build",
        "test"
    ]
    run_command(test_args, cwd=project_dir)

    # 5. Build Release DMG
    print("=== Step 4: Building and packaging DMG ===")
    run_command(["./script/package_dmg.sh"], cwd=project_dir)

    # 6. Sign DMG and generate XML
    print("=== Step 5: Signing update DMG ===")
    sign_output = run_command(["./script/sign_update.py", "LayoutPilot.dmg"], cwd=project_dir)

    # Extract signature from output
    sig_match = re.search(r'Signature \(Ed25519\):\s*([^\n]+)', sign_output)
    if not sig_match:
        print("Error: Could not extract signature from sign_update.py output")
        sys.exit(1)
    signature = sig_match.group(1)

    file_size = os.path.getsize(os.path.join(project_dir, "LayoutPilot.dmg"))
    pub_date = time.strftime("%a, %d %b %Y %H:%M:%S %z", time.localtime())

    new_item_xml = f"""        <item>
            <title>LayoutPilot Update ({release_notes})</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{new_build}</sparkle:version>
            <sparkle:shortVersionString>{new_version}</sparkle:shortVersionString>
            <enclosure 
                url="https://github.com/VelizarSeleznev/LayoutPilot/releases/download/v{new_version}/LayoutPilot.dmg"
                length="{file_size}"
                type="application/octet-stream"
                sparkle:edSignature="{signature}" />
        </item>"""

    # 7. Update docs/appcast.xml
    print("=== Step 6: Updating docs/appcast.xml ===")
    if not os.path.exists(appcast_path):
        print(f"Error: appcast.xml not found at {appcast_path}")
        sys.exit(1)

    with open(appcast_path, "r") as f:
        appcast = f.read()

    if "-->" in appcast:
        parts = appcast.split("-->", 1)
        new_appcast = parts[0] + "-->\n" + new_item_xml + parts[1]
        with open(appcast_path, "w") as f:
            f.write(new_appcast)
    else:
        print("Warning: Could not find comment end '-->' in appcast.xml to prepend item.")

    # 8. Push to GitHub
    print("=== Step 7: Committing and pushing changes ===")
    run_command(["git", "add", "project.yml", "docs/appcast.xml"], cwd=project_dir)
    run_command(["git", "commit", "-m", f"Release version {new_version} (build {new_build})"], cwd=project_dir)
    run_command(["git", "push"], cwd=project_dir)

    # 9. Create GitHub Release
    print("=== Step 8: Creating GitHub Release ===")
    gh_args = [
        "gh", "release", "create", f"v{new_version}",
        "LayoutPilot.dmg",
        "--title", f"Version {new_version}",
        "--notes", release_notes
    ]
    run_command(gh_args, cwd=project_dir)

    print(f"\n=== Success! Release version {new_version} (build {new_build}) published successfully! ===")

if __name__ == "__main__":
    main()
