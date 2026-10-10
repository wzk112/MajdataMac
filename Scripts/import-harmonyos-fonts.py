#!/usr/bin/env python3
"""Extract unchanged, hash-verified fonts from Huawei's official archive."""
import argparse
import hashlib
from pathlib import Path
import urllib.request
import zipfile
import io

SOURCE = "https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip"
FILES = {
    "HarmonyOS_Sans_SC_Regular.ttf": "297b088424be212207df2ce8b98e335468b782aa6b96832af0b8b773d711e2b1",
    "HarmonyOS_Sans_SC_Bold.ttf": "43a424b85e47fb53a17b3b32026a71801f86f8e022ca6798d186b47d39fa5f01",
    "LICENSE.txt": "b2ffec0e6269ee41c3b5fc0345ab37600b46d66ebea6c9c58ff37f517bdfa164",
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--archive", type=Path, help="Optional local official ZIP")
args = parser.parse_args()
archive = args.archive.read_bytes() if args.archive else urllib.request.urlopen(SOURCE, timeout=90).read()
root = Path(__file__).resolve().parents[1]
destination = root / "Sources/MajdataMac/Resources/Fonts"
with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
    files = {name: bundle.read("HarmonyOS Sans/HarmonyOS_Sans_SC/" + name) for name in FILES}
for name, contents in files.items():
    if hashlib.sha256(contents).hexdigest() != FILES[name]:
        raise SystemExit(f"Official archive changed: {name}; review before updating pinned hashes")
destination.mkdir(parents=True, exist_ok=True)
for name, contents in files.items():
    (destination / name).write_bytes(contents)
    print(f"Verified {name}")
(root / "Documentation/HarmonyOS-Sans-License.txt").write_text(files["LICENSE.txt"].rstrip(b"\0").decode("utf-8"), encoding="utf-8")
