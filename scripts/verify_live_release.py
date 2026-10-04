#!/usr/bin/env python3
"""Verify the real website buttons, live feed and complete public installer bytes."""
import hashlib
from html.parser import HTMLParser
import json
import sys
import time
from urllib.request import urlopen
import xml.etree.ElementTree as ET

repo = "susu177990-rgb/otato-prompt"
site = "https://prompt.otato.art"
tag = sys.argv[1]
base = f"https://github.com/{repo}/releases/download/{tag}"
download = f"https://github.com/{repo}/releases/latest/download/oTATo-prompt.dmg"


def fetch(url):
    with urlopen(url, timeout=60) as response:
        return response.read()


class DownloadLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, name, attributes):
        attributes = dict(attributes)
        if name == "a" and "data-download" in attributes:
            self.links.append(attributes.get("href"))


metadata = json.loads(fetch(base + "/release.json"))
if metadata["tag"] != tag:
    raise SystemExit("Release metadata does not identify the requested release.")
# New domain certificates and asset propagation may take a few minutes.
last_error = None
for attempt in range(12):
    try:
        parser = DownloadLinks()
        parser.feed(fetch(site + "/").decode())
        if len(parser.links) != 3 or set(parser.links) != {download}:
            raise ValueError("The three website download buttons must directly target the installer.")
        feed = fetch(site + "/updates/appcast.xml")
        if feed != fetch(base + "/appcast.xml"):
            raise ValueError("The live update feed does not match the published release.")
        enclosure = ET.fromstring(feed).find("./channel/item/enclosure")
        if enclosure is None or enclosure.get("url") != base + "/oTATo-prompt.dmg":
            raise ValueError("The feed must point to an immutable versioned installer URL.")
        digest = hashlib.sha256()
        length = 0
        with urlopen(download, timeout=60) as response:
            disposition = response.headers.get("Content-Disposition", "")
            if "oTATo-prompt.dmg" not in disposition:
                raise ValueError("The download response must identify the DMG attachment.")
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                length += len(chunk)
        if digest.hexdigest() != metadata["sha256"] or length != int(enclosure.get("length")):
            raise ValueError("The public download bytes do not match the verified, signed installer.")
        print(f"PASS: all download buttons, live signed feed and full DMG SHA-256 ({length} bytes)")
        break
    except Exception as error:
        last_error = error
        if attempt == 11:
            raise SystemExit(f"Public release verification failed: {last_error}")
        time.sleep(20)
