#!/usr/bin/env python3
"""
tools/versioning.py — единый источник версий для CI.

Схема унаследована от основного приложения (krasava-app), потому что она себя
оправдала: одна линия версий, каналы выводятся из тега, а номер сборки
считается РОВНО ОДИН РАЗ на запуск и раздаётся всем джобам.

Каналы:
  stable   тег v26.1.0        → 26.1.0
  beta     тег v26.1.0-beta.3 → 26.1.0-beta.3   (prerelease)
  rc       тег v26.1.0-rc.1   → 26.1.0-rc.1     (prerelease)
  dev      push в main        → 26.1.0-dev.N    (rolling preview)
  contrib  ручной запуск      → 26.1.0-contrib.N

`CFBundleVersion` = epoch-секунды. Почему не `github.run_id`: он не влезает в
Int32 и ломает валидацию App Store. Почему не `github.run_started_at`: это
свойство в выражениях workflow рендерится пустым, и каждая джоба молча
подставляла своё «сейчас» — версии расходились.

Версия в репозитории живёт ТОЛЬКО в файле `VERSION`. Полные версии с
суффиксами не коммитятся: их вычисляет CI и передаёт в xcodebuild как
MARKETING_VERSION / CURRENT_PROJECT_VERSION. Файлы проекта не патчатся —
меньше шансов получить грязный git-статус на раннере.

Команды:
  resolve  вывести version/channel/prerelease/build_id в $GITHUB_OUTPUT
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

VERSION_FILE = "VERSION"
MAX_BUILD_ID = 2_147_483_647

# v26.1.0 | v26.1.0-beta.3 | v26.1.0-rc.1
TAG_RE = re.compile(r"^v(\d+\.\d+(?:\.\d+)?)(?:-(beta|rc)\.(\d+))?$")


def read_release_version() -> str:
    path = Path(VERSION_FILE)
    if not path.exists():
        sys.exit(f"Не найден файл {VERSION_FILE} — в нём живёт линия версий.")
    value = path.read_text(encoding="utf-8").strip()
    if not value:
        sys.exit(f"{VERSION_FILE} пуст")
    return value


def short_sha() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], text=True
        ).strip()
    except Exception:
        sha = os.environ.get("GITHUB_SHA", "local")
        return sha[:8] if sha else "local"


def compute_build_id(build_time: str | None) -> int:
    if build_time:
        moment = datetime.fromisoformat(build_time.replace("Z", "+00:00"))
        build_id = int(moment.timestamp())
    else:
        build_id = int(datetime.now(timezone.utc).timestamp())
    if build_id > MAX_BUILD_ID:
        sys.exit(f"build id {build_id} превышает Int32 ({MAX_BUILD_ID}).")
    return build_id


def resolve(tag: str | None, channel: str | None, run_number: int,
            build_id: int, prev_version: str | None) -> dict:
    if tag:
        match = TAG_RE.match(tag.strip())
        if not match:
            sys.exit(
                f"Некорректный тег '{tag}'. Ожидается v26.1.0, "
                f"v26.1.0-beta.3 или v26.1.0-rc.1"
            )
        version = match.group(1)
        channel = match.group(2) or "stable"
        if match.group(2):
            version += f"-{match.group(2)}.{match.group(3)}"
    elif channel == "dev":
        line = read_release_version()
        # Номер dev-сборки продолжает предыдущий той же линии; смена линии
        # сбрасывает счётчик в 1. Отменённые прогоны номер не съедают.
        previous = 0
        if prev_version:
            found = re.search(rf"{re.escape(line)}-dev\.(\d+)", prev_version)
            if found:
                previous = int(found.group(1))
        version = f"{line}-dev.{previous + 1}"
    elif channel == "contrib":
        version = f"{read_release_version()}-contrib.{run_number}"
    else:
        sys.exit("Нужен --tag либо --channel dev/contrib")

    return {
        "version": version,
        "channel": channel,
        "prerelease": "false" if channel == "stable" else "true",
        "build_id": str(build_id),
        "commit_sha": short_sha(),
    }


def emit(info: dict) -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            for key, value in info.items():
                handle.write(f"{key}={value}\n")
    print("=" * 42)
    print("VERSION RESOLVED")
    print(json.dumps(info, indent=2, ensure_ascii=False))
    print("=" * 42)


def main() -> int:
    parser = argparse.ArgumentParser(description="Генератор версий CI")
    parser.add_argument("command", choices=["resolve"])
    parser.add_argument("--channel", default=None, help="dev | contrib")
    parser.add_argument("--tag", default=None, help="v26.1.0, v26.1.0-beta.3, ...")
    parser.add_argument("--run-number", type=int, default=0)
    parser.add_argument("--prev-version", default=None)
    parser.add_argument("--build-time", default=None)
    args = parser.parse_args()

    if not args.tag and not args.channel:
        sys.exit("Нужен --tag или --channel")

    build_id = compute_build_id(args.build_time)
    info = resolve(args.tag, args.channel, args.run_number, build_id, args.prev_version)
    emit(info)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())