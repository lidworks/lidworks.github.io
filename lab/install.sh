#!/bin/bash
# Lidworks Lab installer.
#
#   curl -fsSL https://lidworks.github.io/lab/install.sh | bash
#
# What it does, in order:
#   1. Checks you have an Apple silicon Mac with macOS 13 or later.
#   2. Downloads LidworksLab.zip from our GitHub Releases page into a temporary folder.
#   3. Puts "LidworksLab.app" in /Applications (or ~/Applications if you can't write there),
#      replacing an older copy if there is one.
#   4. Opens it.
# It asks for no password and changes no settings. Files downloaded by Terminal aren't marked
# "from the internet", so macOS opens the app without the "can't verify the developer" prompt.
# To remove it later: use "Delete App and Quit" at the end of the test, or drag it to the Trash.
set -euo pipefail

URL="${LAB_ZIP_URL:-https://github.com/lidworks/lab/releases/latest/download/LidworksLab.zip}"   # LAB_ZIP_URL is only for testing
APP="LidworksLab.app"

case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p)" in
  *zh*) ZH=1 ;;
  *) ZH=0 ;;
esac
say() { if [ "$ZH" = 1 ]; then echo "$2"; else echo "$1"; fi; }
fail() { say "✗ $1" "✗ $2" >&2; exit 1; }

[ "$(uname -m)" = "arm64" ] || fail "Lidworks Lab needs a Mac with Apple silicon." "Lidworks Lab 需要 Apple 芯片的 Mac。"
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 13 ] || fail "Lidworks Lab needs macOS 13 or later." "Lidworks Lab 需要 macOS 13 或更新的系统。"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lidworks-lab.XXXXXX")" || fail "Couldn't create a temporary folder." "建不了临时文件夹。"
trap 'rm -rf "$TMP"' EXIT

say "▸ Downloading Lidworks Lab…" "▸ 正在下载 Lidworks Lab…"
if ! curl -fL --progress-bar --retry 2 "$URL" -o "$TMP/lab.zip"; then
  fail "Download failed. Check your connection, or download it from the website instead." \
       "下载失败。检查一下网络（在中国大陆可能需要代理），或者到网站上手动下载。"
fi
ditto -x -k "$TMP/lab.zip" "$TMP/unzipped"
[ -d "$TMP/unzipped/$APP" ] || fail "The download looks broken. Please try again." "下载的文件好像不完整，请再试一次。"

DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
# If an older copy is running, let it quit normally (it puts the brightness back first)
if pgrep -x LidworksLab >/dev/null 2>&1; then
  osascript -e 'quit app id "app.lidworks.lab"' >/dev/null 2>&1 || true
  sleep 1
fi
rm -rf "${DEST:?}/$APP"
ditto "$TMP/unzipped/$APP" "$DEST/$APP"

say "▸ Opening Lidworks Lab (installed in $DEST)" "▸ 正在打开 Lidworks Lab（装在 ${DEST}）"
open "$DEST/$APP"
say "✓ Done. When the test is finished, you can delete the app from its last screen." \
    "✓ 好了。测试做完后，可以在最后一页直接删除这个 App。"
