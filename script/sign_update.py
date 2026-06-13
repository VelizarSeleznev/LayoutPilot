#!/usr/bin/env python3
import sys
import os
import subprocess
import base64
import time

def main():
    if len(sys.argv) < 2:
        print("Usage: ./script/sign_update.py <path_to_update_file_e.g_LayoutPilot.dmg>")
        sys.exit(1)

    update_file = sys.argv[1]
    if not os.path.exists(update_file):
        print(f"Error: Update file not found at: {update_file}")
        sys.exit(1)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    private_key_path = os.path.join(project_dir, ".build", "keys", "sparkle_private_key.pem")

    if not os.path.exists(private_key_path):
        print(f"Error: Private key not found at: {private_key_path}")
        print("Please ensure you have generated it or that you are running in the correct directory.")
        sys.exit(1)

    # Temporary signature file path
    temp_sig_path = update_file + ".sig.bin"

    try:
        # Sign the file using openssl pkeyutl
        subprocess.run([
            "openssl", "pkeyutl", 
            "-sign", 
            "-inkey", private_key_path, 
            "-rawin", 
            "-in", update_file, 
            "-out", temp_sig_path
        ], check=True)

        # Read the raw signature and encode to base64
        with open(temp_sig_path, "rb") as sig_file:
            raw_signature = sig_file.read()
        
        signature_b64 = base64.b64encode(raw_signature).decode('utf-8')

        # Clean up temp file
        if os.path.exists(temp_sig_path):
            os.remove(temp_sig_path)

        file_size = os.path.getsize(update_file)
        current_time = time.strftime("%a, %d %b %Y %H:%M:%S %z", time.localtime())

        print("\n=== Update Signed Successfully ===")
        print(f"Signature (Ed25519): {signature_b64}")
        print("\n=== Appcast XML Item Template ===")
        print(f"""    <item>
        <title>LayoutPilot Update</title>
        <pubDate>{current_time}</pubDate>
        <sparkle:version>1.1</sparkle:version>
        <sparkle:shortVersionString>1.1</sparkle:shortVersionString>
        <enclosure 
            url="https://github.com/VelizarSeleznev/LayoutPilot/releases/download/v1.1/LayoutPilot.dmg"
            length="{file_size}"
            type="application/octet-stream"
            sparkle:edSignature="{signature_b64}" />
    </item>""")
    
    except Exception as e:
        print(f"Error during signing: {e}")
        if os.path.exists(temp_sig_path):
            os.remove(temp_sig_path)
        sys.exit(1)

if __name__ == "__main__":
    main()
