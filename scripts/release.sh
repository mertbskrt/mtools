#!/usr/bin/env bash
# MTools - build edilmis APK'yi panele yukle (+ istege bagli yayinla)
set -euo pipefail

PANEL="${MTOOLS_PANEL:?Set MTOOLS_PANEL environment variable}"
AUTH="${MTOOLS_AUTH:?MTOOLS_AUTH=kullanici:parola export et}"

APK="${1:?Kullanim: ./scripts/release.sh <apk-yolu> [\"surum notlari\"]}"
NOTES="${2:-}"
[[ -f "$APK" ]] || { echo "APK yok: $APK"; exit 1; }

echo "-> Yukleniyor: $APK"
UP=$(curl -sf -u "$AUTH" -F "apk=@${APK}" "$PANEL/api/upload")
FILE=$(jq -r '.filename'    <<<"$UP")
VER=$(jq -r '.versionName'  <<<"$UP")
CODE=$(jq -r '.versionCode' <<<"$UP")
echo "   Yuklendi: $FILE  (v$VER / $CODE)"

if [[ -z "$NOTES" ]]; then
  echo "-> Panelde gorunuyor. Yayinlamak icin panelden 'Yayina Al' de,"
  echo "   ya da not vererek tekrar calistir: ./scripts/release.sh \"$APK\" \"notlar\""
  exit 0
fi

[[ "$VER" != "null" && "$CODE" != "null" ]] || { echo "HATA: surum APK'dan okunamadi, panelden elle yayinla"; exit 1; }

echo "-> Yayinlaniyor (GitHub release)..."
OUT=$(curl -sf -u "$AUTH" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg f "$FILE" --arg v "$VER" --arg c "$CODE" --arg n "$NOTES" \
        '{filename:$f,version:$v,versionCode:$c,notes:$n}')" \
  "$PANEL/api/publish")
echo "   $(jq -r '.url // .error' <<<"$OUT")"
