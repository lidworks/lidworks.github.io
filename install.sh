#!/bin/bash
# Lidworks installer: puts one of our apps in Applications and opens it.
#
#   curl -fsSL https://lidworks.github.io/install.sh | bash -s <app>
#
#   <app> is one of: steady, hop, stayput, newhere, wipemode
#
# What it does, in order:
#   1. Checks you have an Apple silicon Mac with macOS 13 or later.
#   2. Downloads the app's .zip from its GitHub Releases page (github.com/lidworks/<app>) into a temporary folder.
#   3. Puts the app in /Applications (or ~/Applications if you can't write there), replacing an older copy.
#   4. Opens it. The app then walks you through anything it needs.
# It asks for no password and changes no settings. Files downloaded by Terminal aren't marked
# "from the internet", so macOS opens the app without the "Apple could not verify" prompt.
# To remove an app later: quit it from its menu, then drag it from Applications to the Trash.
set -euo pipefail

case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p)" in
  *zh*) ZH=1 ;;
  *) ZH=0 ;;
esac
say() { if [ "$ZH" = 1 ]; then echo "$2"; else echo "$1"; fi; }
fail() { say "✗ $1" "✗ $2" >&2; exit 1; }

KEY="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
case "$KEY" in
  steady)    NAME="Steady";    REPO="steady";    ID="app.lidworks.steady" ;;
  hop)       NAME="Hop";       REPO="hop";       ID="app.lidworks.hop" ;;
  stayput)   NAME="StayPut";   REPO="stayput";   ID="app.lidworks.stayput" ;;
  newhere)   NAME="NewHere";   REPO="newhere";   ID="app.lidworks.newhere" ;;
  wipemode)  NAME="WipeMode";  REPO="wipemode";  ID="app.lidworks.wipemode" ;;
  *) fail "Tell me which app to install, e.g.:  curl -fsSL https://lidworks.github.io/install.sh | bash -s steady" \
          "请告诉我要装哪个 App，比如：curl -fsSL https://lidworks.github.io/install.sh | bash -s steady" ;;
esac
APP="${NAME}.app"
URL="${LIDWORKS_ZIP_URL:-https://github.com/lidworks/${REPO}/releases/latest/download/${NAME}.zip}"   # LIDWORKS_ZIP_URL is only for testing

[ "$(uname -m)" = "arm64" ] || fail "${NAME} needs a Mac with Apple silicon." "${NAME} 需要 Apple 芯片的 Mac。"
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 13 ] || fail "${NAME} needs macOS 13 or later." "${NAME} 需要 macOS 13 或更新的系统。"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lidworks.XXXXXX")" || fail "Couldn't create a temporary folder." "建不了临时文件夹。"
trap 'rm -rf "$TMP"' EXIT

say "▸ Downloading ${NAME}…" "▸ 正在下载 ${NAME}…"
if ! curl -fL --progress-bar --retry 2 "$URL" -o "$TMP/app.zip"; then
  fail "Download failed. Check your connection, or download the .dmg from lidworks.github.io instead." \
       "下载失败。检查一下网络（在中国大陆可能需要代理），或者到 lidworks.github.io 下载 .dmg。"
fi
ditto -x -k "$TMP/app.zip" "$TMP/unzipped"
[ -d "$TMP/unzipped/$APP" ] || fail "The download looks broken. Please try again." "下载的文件好像不完整，请再试一次。"
# Each app says which macOS it needs (Hop, for example, needs macOS 27)
NEED="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$TMP/unzipped/$APP/Contents/Info.plist" 2>/dev/null || echo 13.0)"
[ "$MAJOR" -ge "${NEED%%.*}" ] || fail "${NAME} needs macOS ${NEED%%.*} or later. This Mac has macOS $(sw_vers -productVersion)." \
                                       "${NAME} 需要 macOS ${NEED%%.*} 或更新的系统，这台 Mac 是 macOS $(sw_vers -productVersion)。"

DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

# If an older copy is running, let it quit normally first (Steady puts your brightness back as it quits)
if pgrep -x "$NAME" >/dev/null 2>&1; then
  say "▸ Quitting the copy that's running…" "▸ 先退出正在运行的旧版…"
  osascript -e "quit app id \"$ID\"" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6; do pgrep -x "$NAME" >/dev/null 2>&1 || break; sleep 0.5; done
fi
rm -rf "${DEST:?}/$APP"
ditto "$TMP/unzipped/$APP" "$DEST/$APP"

say "▸ Opening ${NAME} (installed in ${DEST})" "▸ 正在打开 ${NAME}（装在 ${DEST}）"
open "$DEST/$APP"
say "✓ Done. ${NAME} takes it from here." "✓ 装好了，接下来 ${NAME} 会一步步带你设置。"
