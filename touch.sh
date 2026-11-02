#!/bin/bash
# Lidworks touch test — https://lidworks.github.io/touch.sh
#
# For the new touch-screen MacBook Pro. It answers one question: can an app running in
# the background tell that a finger touched the screen, and how quickly?
# What it does, in about 2 minutes:
#   1. Downloads one small program (touchprobe) into a temporary folder and checks its
#      SHA-256 fingerprint against the one written below.
#   2. The program lists the touch hardware macOS reports (trackpad, touch screen), then
#      listens while you tap, swipe and hover over the screen and tap the trackpad.
#      It only listens, to touch contacts, clicks, gestures and whether the pointer is
#      hidden. Never to key presses. It changes no settings.
#   3. Saves the results as a text file in your home folder and deletes the program.
# It installs nothing, needs no password or permission, and never uploads anything:
# you choose whether to send us the file.
#
# Run:  curl -fsSL https://lidworks.github.io/touch.sh | bash
# Options: --yes (no questions, short steps; for testing). PROBE_LANG=en|zh sets the
# language, PROBE_OUT_DIR=folder where the results go (default: your home folder).
set -u

PROBE_LANG="${PROBE_LANG:-}"
if [ -z "$PROBE_LANG" ]; then
  case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')" in
    *zh*) PROBE_LANG=zh ;;
    *) PROBE_LANG=en ;;
  esac
fi
t() { if [ "$PROBE_LANG" = zh ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }   # t "中文" "English"

PROBE_URL="https://lidworks.github.io/touch/touchprobe"
PROBE_SHA256="f3cef53fda09149c95c71a0b5d77af79a0612081256925a94ab33f9d32bd9fa3"   # set by the build
CONTACT="lidworks@proton.me"
CONTACT_X="@Lidworks312"
YES=0
PID=""
WORK=""
RESULT=""

ask() {
  if [ "$YES" = 1 ]; then echo "${2:-}"; return; fi
  local reply; read -r -p "$1" reply </dev/tty; echo "$reply"
}
tink() { (afplay /System/Library/Sounds/Tink.aiff >/dev/null 2>&1 &); }
shown() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# step <name> <seconds> <what to do>: marks a new step for the probe, then waits for Return or the time limit
step() {
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "✗ $(t "测试程序意外停了" "The test program stopped unexpectedly")"; exit 1
  fi
  echo "step $1" >&3
  sleep 0.3   # lets the probe print its tally of the previous step first
  echo
  echo "▸ $3"
  tink
  if [ "$YES" = 1 ]; then sleep "${YES_STEP_SECONDS:-2}"
  elif [ "$2" -le 5 ]; then sleep "$2"
  else read -r -s -t "$2" </dev/tty; fi
}

cleanup() {
  exec 3>&-   # the probe sees the end of its input, writes its summary and quits
  if [ -n "$PID" ]; then
    local i=0
    while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 25 ]; do sleep 0.2; i=$((i + 1)); done
    kill "$PID" 2>/dev/null
  fi
  [ -n "$WORK" ] && rm -rf "$WORK"
}

on_stop() {
  echo
  echo "$(t "已中止。" "Stopped.")"
  if [ -n "$RESULT" ] && [ -f "$RESULT" ]; then
    echo "$(t "到这里为止的记录：" "What was recorded so far: ")$(shown "$RESULT")"
  fi
  exit 130
}

main() {
  for arg in "$@"; do
    case "$arg" in --yes|-y) YES=1 ;; esac
  done
  if [ "$(uname -s)" != Darwin ] || { [ "$(uname -m)" != arm64 ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ]; }; then
    echo "✗ $(t "这个测试只能在 Apple 芯片的 Mac 上运行。" "This test needs a Mac with Apple silicon.")"
    exit 1
  fi
  local out_dir="${PROBE_OUT_DIR:-$HOME}"   # not the Desktop: Terminal would have to ask for access to it
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/lidworks-touch.XXXXXX")" || { echo "✗ $(t "建不了临时文件夹" "Couldn't create a temporary folder")"; exit 1; }
  trap cleanup EXIT
  trap on_stop INT TERM HUP
  trap '' PIPE

  if [ "$PROBE_LANG" = zh ]; then cat <<'EOF'

  ── Lidworks 触摸测试 · 约 2 分钟 ──
  看看在后台运行的程序能不能知道手指碰了屏幕，有多快。
  只听不改：不记录键盘，不改任何设置，不需要任何权限，跑完自动删除测试程序。

EOF
  else cat <<'EOF'

  ── Lidworks touch test · about 2 minutes ──
  Checks whether a program running in the background can tell that a finger
  touched the screen, and how quickly. It only listens: no key presses, no
  settings changed, no permissions needed. The program is deleted afterwards.

EOF
  fi

  local bin="$WORK/touchprobe" sum
  echo "▸ $(t "下载测试程序（约 200 KB）…" "Downloading the test program (about 200 KB)…")"
  if [ -n "${TOUCHPROBE_BIN:-}" ]; then
    cp "$TOUCHPROBE_BIN" "$bin" || exit 1
  elif ! curl -fsSL --max-time 60 -o "$bin" "$PROBE_URL"; then
    echo "✗ $(t "下载失败，检查一下网络再试" "Download failed. Check the connection and try again")"; exit 1
  fi
  sum="$(shasum -a 256 "$bin" 2>/dev/null | awk '{print $1}')"
  [ -n "$sum" ] || sum="$(openssl dgst -sha256 -r "$bin" 2>/dev/null | awk '{print $1}')"
  if [ "$sum" != "$PROBE_SHA256" ]; then
    echo "✗ $(t "下载的程序和这个脚本里写的指纹对不上，所以没有运行它。网站如果刚更新过，过几分钟再试。" "The download doesn't match the fingerprint in this script, so it was not run. If the site was just updated, try again in a few minutes.")"
    exit 1
  fi
  chmod +x "$bin"
  echo "   ✓ $(t "指纹核对通过" "Fingerprint checked") (SHA-256 ${sum:0:16}…)"
  ask "$(t "   准备好就按回车开始（Ctrl-C 随时中止）" "   Press Return to start (Ctrl-C stops it at any time) ")" >/dev/null

  mkdir -p "$out_dir" 2>/dev/null
  RESULT="$out_dir/lidworks-touch-$(date +%Y%m%d-%H%M%S).txt"
  mkfifo "$WORK/control" || { echo "✗ $(t "建不了控制管道" "Couldn't create a control pipe")"; exit 1; }
  echo
  "$bin" 300 --control --log "$RESULT" < "$WORK/control" &
  PID=$!
  exec 3> "$WORK/control"
  local i=0
  until grep -q 'READY' "$RESULT" 2>/dev/null; do
    if ! kill -0 "$PID" 2>/dev/null || [ "$i" -ge 80 ]; then
      echo "✗ $(t "测试程序没能启动" "The test program didn't start")"; exit 1
    fi
    sleep 0.1; i=$((i + 1))
  done
  if grep -q ' built-in screen-size ' "$RESULT"; then
    echo "   ✓ $(t "找到一个屏幕大小的多点触控设备，很可能就是触摸屏" "Found a screen-sized multitouch device: most likely the touch screen")"
  else
    echo "   ⚠︎ $(t "多点触控设备里没有屏幕大小的。照样测一遍，看点屏幕时别的设备有没有反应" "No screen-sized multitouch device is listed. The test still runs, to see whether anything reacts to the screen")"
  fi

  step quiet 3 "$(t "1/5  先别碰屏幕和触控板（3 秒）" "1/5  Hands off the screen and trackpad (3 seconds)")"
  step taps 25 "$(t "2/5  用一根手指点这个终端窗口 10 下，一秒左右一下。点完按回车（25 秒后自动下一步）" "2/5  Tap this Terminal window 10 times with one finger, about once a second. Press Return when done (moves on by itself after 25 s)")"
  step swipes 15 "$(t "3/5  用一根手指在这个窗口上滑 3 下，哪个方向都行。滑完按回车" "3/5  Swipe one finger across this window 3 times, any direction. Press Return when done")"
  step hover 30 "$(t "4/5  悬停：手指慢慢靠近屏幕，停在离屏幕约 1 厘米处别碰到，停 2 秒，再轻轻点一下。做 3 次，然后按回车" "4/5  Hover: slowly bring a fingertip toward the screen, stop about 1 cm (half an inch) away without touching, hold for 2 seconds, then tap lightly. Do this 3 times, then press Return")"
  step trackpad 15 "$(t "5/5  最后在触控板上轻点 3 下（不是屏幕）。点完按回车" "5/5  Last, tap the trackpad 3 times (not the screen). Press Return when done")"
  echo "end" >&3
  exec 3>&-
  i=0
  while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  PID=""

  local verdict hover screen
  verdict="$(sed -n 's/^VERDICT //p' "$RESULT" | tail -1)"
  hover="$(sed -n 's/^HOVER //p' "$RESULT" | tail -1)"
  screen="$(sed -n 's/^SCREEN //p' "$RESULT" | tail -1)"
  echo
  case "$verdict" in
    screen-visible) echo "✓ $(t "结论：后台程序能读到触摸屏的每一下触摸（走多点触控框架，不需要任何权限）。" "Result: a background program CAN see each touch on the screen (through the multitouch framework, no permission needed).")" ;;
    screen-listed-silent) echo "⚠︎ $(t "结论：触摸屏在设备列表里，但点屏幕的时候没收到数据。" "Result: the touch screen is listed, but no touch data arrived while you tapped it.")" ;;
    other-device-touched) echo "⚠︎ $(t "结论：点屏幕时，有个不是屏幕尺寸的设备（${screen}）收到了数据，要看完整记录。" "Result: while you tapped the screen, a device that isn't screen-sized ($screen) reacted. The full log will tell more.")" ;;
    not-listed) echo "✗ $(t "结论：设备列表里没有触摸屏，点屏幕时多点触控这条路什么也没收到。" "Result: no touch screen in the device list, and the multitouch route saw nothing when you tapped the screen.")" ;;
    *) echo "⚠︎ $(t "没拿到结论，请看完整记录。" "No result line. Please look at the full log.")" ;;
  esac
  case "$hover" in
    "yes -") echo "   $(t "手指还没碰到屏幕就能察觉：有几次只是靠近，也收到了数据。" "It can tell a finger is coming before it touches: a few approaches without touching were picked up too.")" ;;
    yes*) echo "   $(t "手指还没碰到屏幕就能察觉，大约提前 ${hover#yes } 毫秒。" "It can tell a finger is coming before it touches, about ${hover#yes } ms early.")" ;;
    brief*) echo "   $(t "手指碰到之前只提前了一两帧（约 ${hover#brief } 毫秒）。" "A finger shows up only a frame or two before contact (about ${hover#brief } ms).")" ;;
    no) echo "   $(t "没有悬停：手指碰到屏幕那一刻才开始有数据。" "No hover: data starts only when the finger touches.")" ;;
  esac

  echo
  echo "✓ $(t "完整记录：" "Full log: ")$(shown "$RESULT")"
  if [ "$PROBE_LANG" = zh ]; then cat <<EOF
   请把上面的结果拍一张照片；或者把这个文件发到 ${CONTACT}，或在 X 上私信 ${CONTACT_X}。谢谢！
   文件里没有序列号、用户名、电脑名之类能认出你或这台电脑的信息。

EOF
  else cat <<EOF
   Please take a photo of the results above, or send this file to $CONTACT
   (or DM $CONTACT_X on X). Thank you!
   It contains no serial number, user name or computer name.

EOF
  fi
  [ "$YES" = 1 ] || open -R "$RESULT" 2>/dev/null   # shows it in Finder, ready to AirDrop or attach
  local answer
  answer="$(ask "$(t "   直接回车保留文件；在展示机上的话，隔空投送给自己后输入 d 再回车删除：" "   Press Return to keep the file, or type d and Return to delete it from this Mac: ")" "")"
  if [ "$answer" = "d" ]; then
    rm -f "$RESULT"
    echo "   $(t "已删除，没有留下任何文件。" "Deleted. Nothing was left behind.")"
  fi
}

if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
