#!/usr/bin/env python3
"""Verify website ZIP contents, the live feed and the signed DMG update bytes."""
import hashlib
from html.parser import HTMLParser
import io
import json
import sys
import time
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
import zipfile

repo = "susu177990-rgb/otato-prompt"
site = "https://prompt.otato.art"
tag = sys.argv[1]
base = f"https://github.com/{repo}/releases/download/{tag}"
download = f"https://github.com/{repo}/releases/latest/download/oTATo-prompt.zip"


def request(url):
    # Identify CI requests explicitly; Cloudflare rejects the generic urllib agent.
    return Request(url, headers={"User-Agent": "oTATo-release-verifier/1.0"})


def fetch(url):
    with urlopen(request(url), timeout=60) as response:
        return response.read()


def fetch_attachment(url, filename):
    with urlopen(request(url), timeout=60) as response:
        if filename not in response.headers.get("Content-Disposition", ""):
            raise ValueError(f"The download response must identify the {filename} attachment.")
        return response.read()


def checksum(data):
    return hashlib.sha256(data).hexdigest()


class DownloadLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, name, attributes):
        attributes = dict(attributes)
        if name == "a" and "data-download" in attributes:
            self.links.append(attributes.get("href"))


metadata = json.loads(fetch(base + "/release.json"))
if metadata["tag"] != tag or metadata.get("download") != "oTATo-prompt.zip":
    raise SystemExit("Release metadata must identify this release and its website ZIP.")
# New domain certificates and asset propagation may take a few minutes.
for attempt in range(12):
    try:
        parser = DownloadLinks()
        parser.feed(fetch(site + "/").decode())
        if len(parser.links) != 3 or set(parser.links) != {download}:
            raise ValueError("The three website download buttons must directly target the ZIP.")
        feed = fetch(site + "/updates/appcast.xml")
        if feed != fetch(base + "/appcast.xml"):
            raise ValueError("The live update feed does not match the published release.")
        enclosure = ET.fromstring(feed).find("./channel/item/enclosure")
        if enclosure is None or enclosure.get("url") != base + "/oTATo-prompt.dmg":
            raise ValueError("Sparkle must keep using the immutable signed DMG URL.")
        signature_key = "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"
        if not enclosure.get(signature_key):
            raise ValueError("The DMG update must have an EdDSA signature.")
        zipped = fetch_attachment(download, metadata["download"])
        if checksum(zipped) != metadata["download_sha256"] or len(zipped) != metadata["download_size"]:
            raise ValueError("The public ZIP bytes do not match the verified download.")
        with zipfile.ZipFile(io.BytesIO(zipped)) as archive:
            expected = [metadata["dmg"], metadata["installation_guide"]]
            if len(archive.namelist()) != 2 or set(archive.namelist()) != set(expected):
                raise ValueError("The ZIP must contain only the DMG and installation PDF, side by side.")
            dmg = archive.read(metadata["dmg"])
            guide = archive.read(metadata["installation_guide"])
        if not guide.startswith(b"%PDF-") or checksum(guide) != metadata["installation_guide_sha256"]:
            raise ValueError("The ZIP must contain the verified installation PDF.")
        if checksum(dmg) != metadata["sha256"] or len(dmg) != int(enclosure.get("length")):
            raise ValueError("The ZIP's DMG does not match the signed update.")
        update = fetch_attachment(enclosure.get("url"), metadata["dmg"])
        if update != dmg:
            raise ValueError("The updater's public DMG differs from the DMG in the ZIP.")
        print(f"PASS: three ZIP downloads, external PDF, live signed feed and matching DMG ({len(zipped)} ZIP bytes)")
        break
    except Exception as error:
        if attempt == 11:
            raise SystemExit(f"Public release verification failed: {error}")
        time.sleep(20)
