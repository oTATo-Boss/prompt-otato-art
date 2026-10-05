#!/usr/bin/env python3
"""Stage only public site files and the appcast of a verified release."""
import argparse
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
mode = parser.add_mutually_exclusive_group(required=True)
mode.add_argument("--appcast", type=Path)
mode.add_argument("--preview", action="store_true", help="Show that the formal download is not open yet.")
args = parser.parse_args()
output = root / ".build/website"
if output.exists():
    shutil.rmtree(output)
output.mkdir(parents=True)
for path in (root / "website").iterdir():
    if path.name == "assets":
        shutil.copytree(path, output / path.name)
    elif path.suffix == ".html" or path.name in ("_headers", "_redirects", "robots.txt"):
        shutil.copy2(path, output / path.name)
if args.appcast:
    enclosure = ET.parse(args.appcast).find("./channel/item/enclosure")
    if enclosure is None or not enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"):
        raise SystemExit("Only a signed release appcast may be staged.")
    updates = output / "updates"
    updates.mkdir()
    shutil.copy2(args.appcast, updates / "appcast.xml")
else:
    index = output / "index.html"
    def pending_download(match):
        anchor = match.group(0)
        anchor = re.sub(r' href="[^"]*"', '', anchor)
        anchor = re.sub(r' target="[^"]*"', '', anchor)
        anchor = re.sub(r' aria-label="[^"]*"', '', anchor)
        anchor = anchor.replace('data-download', 'data-download aria-disabled="true" tabindex="-1"')
        anchor = anchor.replace('下载 macOS 版', '正式版准备中')
        return anchor
    index.write_text(re.sub(r'<a\b[^>]*\bdata-download\b[^>]*>.*?</a>', pending_download,
                           index.read_text(), flags=re.DOTALL))
print(f"Website staged at {output}; appcast included: {bool(args.appcast)}")
