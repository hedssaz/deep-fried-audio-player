#!/usr/bin/env python3
"""Check Swift localization keys against the Xcode string catalog."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "Deep-Fried Audio Player"
CATALOG = APP_DIR / "Localizable.xcstrings"
REQUIRED_LOCALES = ("en", "zh-Hans")

LOCALIZATION_PREFIXES = (
    "audio.",
    "choice.",
    "codec.",
    "control.",
    "editor.",
    "effect.",
    "home.",
    "mode.",
    "parameter.",
    "playback.",
    "processing.",
    "section.",
    "singleModule.",
    "unit.",
    "waveform.",
    "workflow.",
)

INTERNAL_NONLOCALIZED_KEYS = {
    "workflow.singleModulePreview",
}


def swift_string_literals(source: str) -> list[tuple[str, int]]:
    pattern = re.compile(r'"((?:[^"\\]|\\.)*)"')
    result: list[tuple[str, int]] = []

    for match in pattern.finditer(source):
        literal = match.group(1)
        try:
            value = json.loads(f'"{literal}"')
        except json.JSONDecodeError:
            value = literal
        result.append((value, match.start()))

    return result


def is_system_image_argument(source: str, start: int) -> bool:
    line_start = source.rfind("\n", 0, start) + 1
    return "systemImage:" in source[line_start:start]


def collect_used_keys() -> dict[str, list[Path]]:
    used: dict[str, list[Path]] = {}

    for path in APP_DIR.rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        for value, start in swift_string_literals(source):
            if value in INTERNAL_NONLOCALIZED_KEYS or is_system_image_argument(source, start):
                continue

            if value.startswith(LOCALIZATION_PREFIXES):
                used.setdefault(value, []).append(path.relative_to(ROOT))

    return used


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.get("strings", {})
    used = collect_used_keys()

    failures: list[str] = []
    for key, paths in sorted(used.items()):
        entry = strings.get(key)
        if entry is None:
            locations = ", ".join(str(path) for path in sorted(set(paths)))
            failures.append(f"missing key: {key} ({locations})")
            continue

        localizations = entry.get("localizations", {})
        for locale in REQUIRED_LOCALES:
            value = localizations.get(locale, {}).get("stringUnit", {}).get("value", "")
            if not value.strip():
                failures.append(f"missing {locale} translation: {key}")

    if failures:
        print("Localization key check failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(f"Localization key check passed for {len(used)} used keys.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
