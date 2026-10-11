#!/bin/bash
set -Eeuo pipefail

REPO="team-oze/Legion-TD"
API="https://api.github.com/repos/${REPO}/releases/latest"
MAP_DIR="${HOME}/Library/Application Support/Blizzard/Warcraft III/Maps/Download"

echo "=== Legion TD updater ==="

command -v curl >/dev/null || {
    echo "Помилка: curl не знайдено."
    exit 1
}
command -v python3 >/dev/null || {
    echo "Помилка: потрібен Python 3."
    exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Отримую інформацію про останній реліз..."

curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "$API" -o "$TMP_DIR/release.json"

python3 - "$TMP_DIR/release.json" "$TMP_DIR/asset.txt" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)

assets = [
    a for a in release.get("assets", [])
    if a["name"].lower().endswith((".w3x", ".w3m"))
]

if not assets:
    sys.exit("Помилка: у релізі не знайдено файл .w3x або .w3m.")

# Перебір карт:
assets.sort(key=lambda a: (
    not a["name"].lower().endswith(".w3x"),
    "legion" not in a["name"].lower(),
    a["name"].lower()
))
asset = assets[0]

with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write(asset["browser_download_url"] + "\n")
    f.write(asset["name"] + "\n")

print("Реліз:", release.get("tag_name", "невідомий"))
print("Файл:", asset["name"])
PY

DOWNLOAD_URL="$(sed -n '1p' "$TMP_DIR/asset.txt")"
ASSET_NAME="$(sed -n '2p' "$TMP_DIR/asset.txt")"
DEST="$MAP_DIR/$ASSET_NAME"

mkdir -p "$MAP_DIR"

if [[ -f "$DEST" ]]; then
    echo "Карта вже існує: $DEST"
    echo "Перевіряю, чи файл змінився..."
    if curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET_NAME"; then
        if cmp -s "$DEST" "$TMP_DIR/$ASSET_NAME"; then
            echo "Вже встановлена актуальна версія."
            exit 0
        fi
    else
        echo "Не вдалося завантажити карту."
        exit 1
    fi
else
    echo "Завантажую карту..."
    curl -fL --retry 3 "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET_NAME"
fi

if [[ ! -s "$TMP_DIR/$ASSET_NAME" ]]; then
    echo "Помилка: завантажений файл порожній."
    exit 1
fi

# Не залишити частково записану карту.
mv "$TMP_DIR/$ASSET_NAME" "$DEST"

echo
echo "Готово!"
echo "Встановлено: $DEST"

