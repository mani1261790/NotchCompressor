#!/usr/bin/env python3
"""Check app-owned localization catalogs and literal lookup keys without building."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
catalogs = {}
for language in ("en", "ja"):
    path = ROOT / f"Sources/NotchCompressorCore/Resources/{language}.lproj/Localizable.strings"
    entries = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");', line)
        if not match:
            raise SystemExit(f"{path}:{number}: invalid catalog entry")
        key, value = (json.loads(part) for part in match.groups())
        if key in entries:
            raise SystemExit(f"{path}:{number}: duplicate key {key}")
        if "%" in value.replace("%@", "").replace("%%", ""):
            raise SystemExit(f"{path}:{number}: unsupported or unescaped format in {key}")
        entries[key] = value
    catalogs[language] = entries
if catalogs["en"].keys() != catalogs["ja"].keys():
    raise SystemExit("English and Japanese catalog keys differ")
for key, english in catalogs["en"].items():
    if english.count("%@") != catalogs["ja"][key].count("%@"):
        raise SystemExit(f"Placeholder mismatch: {key}")
    if re.search(r"[ぁ-んァ-ヶ一-龠]", english):
        raise SystemExit(f"Japanese text in English catalog: {key}")
lookups = set()
for path in (ROOT / "Sources").rglob("*.swift"):
    lookups.update(re.findall(r'L10n\.text\("([^"\\]+)"', path.read_text()))
missing = lookups - catalogs["en"].keys()
if missing:
    raise SystemExit(f"Missing lookup keys: {sorted(missing)}")
print(f"Both languages: {len(catalogs['en'])} unique keys; {len(lookups)} literal lookups resolved")
