#!/usr/bin/env python3
"""Import CI credentials into an ephemeral Keychain without printing secrets."""
import base64
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

required = ("DEVELOPER_ID_P12", "DEVELOPER_ID_P12_PASSWORD", "APPLE_ID",
            "APPLE_APP_PASSWORD", "APPLE_TEAM_ID", "SPARKLE_PRIVATE_KEY")
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit("Missing release secrets: " + ", ".join(missing))
if os.environ.get("CI") != "true":
    raise SystemExit("This setup is exclusively for an ephemeral CI runner.")


def secure_run(arguments):
    # Command arguments may contain credentials: never log the invocation or output.
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise SystemExit(f"Credential setup failed in {Path(arguments[0]).name}; exit {result.returncode}.")


root = Path(__file__).resolve().parents[1]
password = secrets.token_urlsafe(32)
keychain = str(Path(os.environ["RUNNER_TEMP"]) / "otato-release.keychain-db")
secure_run(["security", "create-keychain", "-p", password, keychain])
secure_run(["security", "set-keychain-settings", "-lut", "21600", keychain])
secure_run(["security", "unlock-keychain", "-p", password, keychain])
secure_run(["security", "list-keychains", "-d", "user", "-s", keychain])
secure_run(["security", "default-keychain", "-d", "user", "-s", keychain])
with tempfile.TemporaryDirectory(dir=os.environ["RUNNER_TEMP"]) as temporary:
    certificate = Path(temporary) / "developer-id.p12"
    certificate.write_bytes(base64.b64decode(os.environ["DEVELOPER_ID_P12"], validate=True))
    certificate.chmod(0o600)
    secure_run(["security", "import", str(certificate), "-k", keychain,
                "-P", os.environ["DEVELOPER_ID_P12_PASSWORD"], "-T", "/usr/bin/codesign"])
    secure_run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                "-s", "-k", password, keychain])
    private = Path(temporary) / "sparkle-key"
    private.write_text(os.environ["SPARKLE_PRIVATE_KEY"])
    private.chmod(0o600)
    tools = root / ".build/packages/SourcePackages/artifacts/sparkle/Sparkle/bin"
    secure_run([str(tools / "generate_keys"), "--account", "art.otato.prompt", "-f", str(private)])
secure_run(["xcrun", "notarytool", "store-credentials", "OTATO_NOTARY", "--keychain", keychain,
            "--apple-id", os.environ["APPLE_ID"], "--team-id", os.environ["APPLE_TEAM_ID"],
            "--password", os.environ["APPLE_APP_PASSWORD"]])
print("Release credentials installed in the temporary runner Keychain.")
