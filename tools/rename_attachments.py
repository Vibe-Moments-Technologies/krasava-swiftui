#!/usr/bin/env python3
"""
tools/rename_attachments.py — вернуть вложениям тестов человеческие имена.

`xcrun xcresulttool export attachments` выгружает файлы под случайными именами
и кладёт рядом `manifest.json`, где записано исходное имя вложения. Без
переименования в артефакте лежит набор UUID.png, и понять, где какой экран,
можно только через манифест — а смотреть на картинки глазами удобнее по имени.

Использование:
    python3 tools/rename_attachments.py snapshots
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def iter_attachments(node):
    """Вложения из манифеста: структура менялась между версиями Xcode."""
    if isinstance(node, list):
        for item in node:
            yield from iter_attachments(item)
    elif isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for value in node.values():
            if isinstance(value, (list, dict)):
                yield from iter_attachments(value)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: rename_attachments.py <snapshots-dir>", file=sys.stderr)
        return 2

    directory = Path(argv[1])
    manifest_path = directory / "manifest.json"
    if not manifest_path.exists():
        print("manifest.json не найден — переименовывать нечего")
        return 0

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        print("manifest.json не читается")
        return 0

    renamed = 0
    for attachment in iter_attachments(manifest):
        exported = attachment.get("exportedFileName")
        readable = attachment.get("suggestedHumanReadableName")
        if not exported or not readable:
            continue

        source = directory / exported
        if not source.exists():
            continue

        suffix = source.suffix or ".png"
        target = directory / f"{readable}{suffix}"

        # Одно и то же имя может прийти из разных тестов — не затираем.
        counter = 1
        while target.exists():
            target = directory / f"{readable}-{counter}{suffix}"
            counter += 1

        source.rename(target)
        renamed += 1

    print(f"переименовано: {renamed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))