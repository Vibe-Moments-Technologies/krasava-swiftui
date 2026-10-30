#!/usr/bin/env bash
#
# Сборка приложения под устройство без подписи.
#
# Почему отдельный скрипт: разные образы macos-26 по-разному разрешают
# дестинации. На одном сборка проходит через `-destination generic/platform=iOS`,
# на другом тот же вызов отвечает «iOS 26.0 is not installed, please download
# the platform», хотя iphoneos-SDK на месте, а `-sdk iphoneos` после этого
# работает. Поведение плавает от ранера к ранеру, поэтому пробуем оба способа
# подряд вместо того, чтобы зашивать один и ловить случайные падения.
#
# Переменные окружения (все необязательные):
#   PROJECT, SCHEME, CONFIGURATION, DERIVED
#   MARKETING_VERSION, CURRENT_PROJECT_VERSION — прокидываются в xcodebuild
#   как build settings, поэтому файлы проекта при сборке не патчатся.
#
set -euo pipefail

PROJECT="${PROJECT:-KrasavaSwiftUI.xcodeproj}"
SCHEME="${SCHEME:-KrasavaSwiftUI}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED="${DERIVED:-build}"

COMMON=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  COMPILER_INDEX_STORE_ENABLE=NO
)

if [ -n "${MARKETING_VERSION:-}" ]; then
  COMMON+=("MARKETING_VERSION=$MARKETING_VERSION")
fi
if [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
  COMMON+=("CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION")
fi

attempt() {
  local label="$1"
  shift
  echo "==> Сборка: $label"
  if xcodebuild build "${COMMON[@]}" "$@"; then
    echo "==> Успешно: $label"
    return 0
  fi
  echo "::warning::Способ «$label» не сработал, пробуем следующий."
  return 1
}

if attempt "generic/platform=iOS" -destination 'generic/platform=iOS'; then
  exit 0
fi

if attempt "-sdk iphoneos" -sdk iphoneos; then
  exit 0
fi

echo "::error::Сборка под устройство не удалась ни через generic destination, ни через -sdk iphoneos."
exit 1