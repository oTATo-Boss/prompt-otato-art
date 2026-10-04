#!/usr/bin/env python3
"""Build and verify Developer ID releases. Never accepts unsigned substitutes."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REPO = "susu177990-rgb/otato-prompt"
SITE = "https://prompt.otato.art"
SPARKLE_ACCOUNT = "art.otato.prompt"


def run(args, *, capture=False, stdin=None):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, input=stdin,
                            text=True, capture_output=capture, check=True)
    return result.stdout.strip() if capture else ""


def identities():
    output = run(["security", "find-identity", "-v", "-p", "codesigning"], capture=True)
    return re.findall(r'([A-F0-9]{40}) "(Developer ID Application: [^\n]+)"', output)


def sparkle_bin(derived):
    directory = derived / "SourcePackages/artifacts/sparkle/Sparkle/bin"
    if not (directory / "generate_appcast").is_file():
        raise RuntimeError("Sparkle release tools are missing from resolved Xcode packages.")
    return directory


def plist(path):
    with path.open("rb") as handle:
        return plistlib.load(handle)


def validate_app(app, version, build):
    info = plist(app / "Contents/Info.plist")
    expected = {"CFBundleIdentifier": "art.otato.prompt",
                "CFBundleShortVersionString": version, "CFBundleVersion": str(build),
                "SUFeedURL": SITE + "/updates/appcast.xml",
                "SUEnableAutomaticChecks": True, "SUScheduledCheckInterval": 3600,
                "SUAutomaticallyUpdate": False, "SUVerifyUpdateBeforeExtraction": True}
    for key, value in expected.items():
        if info.get(key) != value:
            raise RuntimeError(f"Unexpected {key}: {info.get(key)!r}; expected {value!r}.")
    if info.get("LSMinimumSystemVersion") != "14.0":
        raise RuntimeError("Confirm system support before changing the minimum macOS version.")
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    archs = set(run(["lipo", "-archs", binary], capture=True).split())
    if archs != {"arm64", "x86_64"}:
        raise RuntimeError(f"Expected a Universal app; found {archs}.")
    run(["codesign", "--verify", "--deep", "--strict", app])
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)],
                             capture_output=True, text=True, check=True).stderr
    if "Authority=Developer ID Application:" not in details or "runtime" not in details:
        raise RuntimeError("The app must use Developer ID signing and Hardened Runtime.")
    entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)],
                                  capture_output=True, check=True).stdout
    if plistlib.loads(entitlements).get("com.apple.security.get-task-allow", False):
        raise RuntimeError("A distributable app must not allow debugger attachment.")
    return info


def notarize(path, profile):
    output = run(["xcrun", "notarytool", "submit", path, "--keychain-profile", profile,
                  "--wait", "--output-format", "json"], capture=True)
    result = json.loads(output)
    if result.get("status") != "Accepted":
        raise RuntimeError(f"Apple notarization failed: {result.get('status')}; "
                           f"submission {result.get('id')}. Inspect it with notarytool log.")
    run(["xcrun", "stapler", "staple", path])
    run(["xcrun", "stapler", "validate", path])


def next_build():
    releases = json.loads(run(["gh", "api", f"repos/{REPO}/releases?per_page=100"], capture=True))
    numbers = [int(match.group(1)) for release in releases
               if (match := re.search(r"-build(\d+)$", release["tag_name"]))]
    configured = re.search(r"CURRENT_PROJECT_VERSION = (\d+);",
                           (ROOT / "oTATo Prompt.xcodeproj/project.pbxproj").read_text())
    print(max([int(configured.group(1)), *[n + 1 for n in numbers]]))


def build_release(args):
    matches = identities()
    if args.identity:
        matches = [(sha, name) for sha, name in matches
                   if args.identity in (sha, name)]
    if len(matches) != 1:
        raise RuntimeError("Install one valid Developer ID Application certificate with its "
                           "private key, or select it with --identity. No unsigned release was created.")
    identity, identity_name = matches[0]
    team_match = re.search(r"\(([A-Z0-9]{10})\)$", identity_name)
    if not team_match:
        raise RuntimeError("Could not determine the Developer ID team.")
    team = team_match.group(1)
    work = ROOT / ".build/releases" / args.tag
    output = ROOT / "dist/releases" / args.tag
    if run(["git", "status", "--porcelain"], capture=True):
        raise RuntimeError("Commit the release source and start from a clean working tree.")
    if output.exists():
        raise RuntimeError(f"Output already exists: {output}. Use a new build number.")
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True)
    derived = work / "derived"
    archive = work / "oTATo.xcarchive"
    export = work / "export"
    run(["xcodebuild", "-project", "oTATo Prompt.xcodeproj", "-scheme", "oTATo Prompt",
         "-configuration", "Release", "-destination", "generic/platform=macOS",
         "-derivedDataPath", derived, "-archivePath", archive,
         "ONLY_ACTIVE_ARCH=NO", "ARCHS=arm64 x86_64", "SWIFT_ACTIVE_COMPILATION_CONDITIONS=",
         "ENABLE_HARDENED_RUNTIME=YES", "ENABLE_DEBUG_DYLIB=NO", "CODE_SIGN_STYLE=Manual",
         f"CODE_SIGN_IDENTITY={identity}", f"DEVELOPMENT_TEAM={team}",
         f"MARKETING_VERSION={args.version}", f"CURRENT_PROJECT_VERSION={args.build}", "archive"])
    options = work / "ExportOptions.plist"
    with options.open("wb") as handle:
        plistlib.dump({"method": "developer-id", "teamID": team, "signingStyle": "manual",
                      "signingCertificate": identity, "destination": "export"}, handle)
    run(["xcodebuild", "-exportArchive", "-archivePath", archive,
         "-exportPath", export, "-exportOptionsPlist", options])
    app = export / "oTATo Prompt.app"
    info = validate_app(app, args.version, args.build)
    tools = sparkle_bin(derived)
    public = run([tools / "generate_keys", "--account", SPARKLE_ACCOUNT, "-p"], capture=True)
    if public != info["SUPublicEDKey"]:
        raise RuntimeError("The Sparkle key in the Keychain does not match the app's public key.")
    zipped = work / "notarization.zip"
    run(["ditto", "-c", "-k", "--keepParent", app, zipped])
    # The ticket for the ZIP submission is stapled to its contained app.
    submission = json.loads(run(["xcrun", "notarytool", "submit", zipped,
                                 "--keychain-profile", args.notary_profile, "--wait",
                                 "--output-format", "json"], capture=True))
    if submission.get("status") != "Accepted":
        raise RuntimeError(f"App notarization failed: {submission.get('status')}; "
                           f"submission {submission.get('id')}.")
    run(["xcrun", "stapler", "staple", app])
    run(["xcrun", "stapler", "validate", app])
    run(["spctl", "--assess", "--type", "execute", "--verbose=2", app])
    dmg = output / "oTATo-prompt.dmg"
    run([sys.executable, "-m", "dmgbuild", "-s", ROOT / "packaging/dmg/settings.py",
         "-D", f"app={app}", "oTATo prompt 安装", dmg])
    run(["codesign", "--force", "--sign", identity, "--timestamp", dmg])
    notarize(dmg, args.notary_profile)
    run(["codesign", "--verify", "--strict", dmg])
    run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", dmg])
    run(["hdiutil", "verify", dmg])
    notes = Path(args.notes).resolve()
    if not notes.is_file() or not notes.read_text().strip():
        raise RuntimeError("Provide release notes with --notes.")
    shutil.copy2(notes, output / "oTATo-prompt.md")
    run([tools / "generate_appcast", "--account", SPARKLE_ACCOUNT,
         "--download-url-prefix", f"https://github.com/{REPO}/releases/download/{args.tag}/",
         "--link", SITE, "--embed-release-notes", "--maximum-deltas", "0", output])
    feed = output / "appcast.xml"
    enclosure = ET.parse(feed).find("./channel/item/enclosure")
    ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    if enclosure is None or not enclosure.get(ns + "edSignature"):
        raise RuntimeError("The generated update feed has no EdDSA signature.")
    if int(enclosure.get("length")) != dmg.stat().st_size:
        raise RuntimeError("The update feed size does not match the final installer.")
    run([tools / "sign_update", "--account", SPARKLE_ACCOUNT, "--verify", dmg,
         enclosure.get(ns + "edSignature")])
    with dmg.open("rb") as handle:
        checksum = hashlib.file_digest(handle, "sha256").hexdigest()
    (output / "release.json").write_text(json.dumps({
        "tag": args.tag, "version": args.version, "build": args.build,
        "commit": run(["git", "rev-parse", "HEAD"], capture=True),
        "team": team, "dmg": dmg.name, "appcast": feed.name,
        "sha256": checksum,
    }, indent=2) + "\n")
    print(f"Verified signed and notarized release: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("next-build")
    sub.add_parser("preflight")
    build = sub.add_parser("build")
    build.add_argument("--version", required=True)
    build.add_argument("--build", type=int, required=True)
    build.add_argument("--tag", required=True)
    build.add_argument("--notes", required=True)
    build.add_argument("--identity")
    build.add_argument("--notary-profile", default="OTATO_NOTARY")
    args = parser.parse_args()
    try:
        if args.command == "next-build":
            next_build()
        elif args.command == "preflight":
            valid = identities()
            print(f"Valid Developer ID Application identities: {len(valid)}")
            if not valid:
                raise RuntimeError("Developer ID signing is unavailable on this Mac.")
        else:
            if not re.fullmatch(r"\d+(?:\.\d+){0,2}", args.version):
                raise RuntimeError("Use a numeric release version, such as 1.0 or 1.0.1.")
            if not 1 <= args.build <= 9999:
                raise RuntimeError("The integer build number must be between 1 and 9999.")
            if args.tag != f"v{args.version}-build{args.build}":
                raise RuntimeError("The release tag must identify the exact version and build.")
            build_release(args)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
