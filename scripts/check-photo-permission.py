#!/usr/bin/env python3
"""Check the shipped permission description after Xcode processes Info.plist."""
import argparse
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('plist', type=Path, help='Built app or archive app Info.plist')
args = parser.parse_args()
with args.plist.open('rb') as source:
    info = plistlib.load(source)

key = 'NSPhotoLibraryAddUsageDescription'
description = info.get(key)
if not isinstance(description, str) or not description.strip() or '$(' in description:
    raise SystemExit(f'{args.plist}: {key} must contain a nonempty, resolved purpose string')
print(f'{args.plist}: photo-library additions purpose string verified')
