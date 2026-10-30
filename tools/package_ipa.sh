#!/usr/bin/env bash
#
# Упаковка собранного .app в непечатанный (unsigned) IPA.
#
# Что делает:
#  1. находит .app в DerivedData;
#  2. подписывает ad-hoc (identity "-") вложенный .appex и само приложение
#     с entitlements — в них заявлена App Group, без которой виджет после
#     переподписи сторонним сертификатом останется без общего контейнера;
#  3. складывает всё в Payload/ и пакует в zip с расширением .ipa.
#
# Переменные окружения:
#   DERIVED — путь DerivedData (по умолчанию build)
#   OUTPUT  — имя итогового файла (по умолчанию KrasavaSwiftUI.ipa)
#
set -euo pipefail

DERIVED="${DERIVED:-build}"
OUTPUT="${OUTPUT:-KrasavaSwiftUI.ipa}"
PRODUCTS="$DERIVED/Build/Products/Release-iphoneos"

APP_PATH=$(find "$PRODUCTS" -maxdepth 1 -name "*.app" -type d | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "::error::Собранный .app не найден в $PRODUCTS"
  ls -la "$PRODUCTS" 2>/dev/null || true
  exit 1
fi
echo "==> Приложение: $APP_PATH"

# Вложенные бандлы подписываются ПЕРВЫМИ: иначе подпись контейнера
# разваливается при последующей подписи вложенного.
if [ -d "$APP_PATH/PlugIns/KrasavaWidget.appex" ]; then
  echo "==> Ad-hoc подпись расширения виджета"
  codesign --force --sign - \
    --entitlements Support/KrasavaWidget.entitlements \
    "$APP_PATH/PlugIns/KrasavaWidget.appex"
fi

echo "==> Ad-hoc подпись приложения"
codesign --force --sign - \
  --entitlements Support/KrasavaSwiftUI.entitlements \
  "$APP_PATH"

echo "==> Entitlements приложения"
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || true

# Payload/<App>.app — структура, которую понимают все инструменты sideload.
rm -rf Payload "$OUTPUT"
mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry "$OUTPUT" Payload
rm -rf Payload

ls -lh "$OUTPUT"
echo "==> Готово: $OUTPUT"