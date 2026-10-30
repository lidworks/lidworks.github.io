#!/bin/bash
# Lidworks logo probe — https://lidworks.github.io/test
#
# Helps us learn how the glowing logo on the new MacBook Pro (PROLED) is controlled.
# What it does, in about 3 minutes:
#   1. Saves a list of your Mac's hardware (ioreg, hidutil, system_profiler).
#      Serial numbers, UUIDs, MAC addresses and your user name are removed.
#   2. Steps the screen brightness up and down, and darkens the picture for 6 seconds,
#      while you film the logo with your phone.
#   3. Restores your brightness, then zips the results on your Desktop.
# It installs nothing, needs no password, and never uploads anything: you choose
# whether to send us the zip. Optional: a 1-minute touch test of our free app WipeMode
# (downloaded to a temporary folder and deleted afterwards).
#
# Run:  curl -fsSL https://lidworks.github.io/probe.sh | bash

set -u

PROBE_LANG="${PROBE_LANG:-}"
if [ -z "$PROBE_LANG" ]; then
  case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')" in
    *zh*) PROBE_LANG=zh ;;
    *) PROBE_LANG=en ;;
  esac
fi
t() { if [ "$PROBE_LANG" = zh ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

export LC_ALL=C

CONTACT="lidworks@proton.me"
CONTACT_X="@Lidworks312"

ts()   { date +%H:%M:%S; }
say_bg() { (say -r 190 "$1" >/dev/null 2>&1 &); }
tink() { (afplay /System/Library/Sounds/Tink.aiff >/dev/null 2>&1 &); }
YES=0
ask()  {
  if [ "$YES" = 1 ]; then echo "${2:-}"; return; fi
  local reply; read -r -p "$1" reply </dev/tty; echo "$reply"
}

nits() {
  ioreg -r -c IOMobileFramebufferShim -w0 2>/dev/null \
    | awk -F' = ' '/"IOMFBBrightnessLevel"/ { v = $2 / 65536; if (v > m) m = v } END { printf "%.1f", m }'
}

redact() {
  sed -E \
    -e '/"[^"]*([Ss]erial|UUID|UDID|[Mm]ac-?[Aa]ddress|MACAddress|BD_ADDR|[Ii]mei|ECID)[^"]*" = /s/ = .*/ = <redacted>/' \
    -e '/(Serial Number|Hardware UUID|Provisioning UDID|UUID)[^:]*:/s/:.*/: <redacted>/' \
    -e 's/("kCGS?Session(Long)?UserNameKey"=)"[^"]*"/\1"<redacted>"/g' \
    -e 's#/Users/[^/" ]+#/Users/<user>#g'
}

normalize() {
  awk '
    /\+-o / {
      line = $0; sub(/^.*\+-o /, "", line)
      name = line; sub(/  <class.*/, "", name)
      id = "?"; if (match(line, /id 0x[0-9a-f]+/)) id = substr(line, RSTART + 3, RLENGTH - 3)
      node = name "@" id
      next
    }
    /"[^"]+" = / {
      line = $0; sub(/^[ |]*/, "", line)
      key = line; sub(/" = .*/, "\"", key)
      val = line; sub(/^"[^"]*" = /, "", val)
      print node "\t" key "\t" val
    }' "$1"
}

changed() {
  awk -F'\t' '
    NR == FNR { a[$1 FS $2] = $3; next }
    (($1 FS $2) in a) && a[$1 FS $2] != $3 { print $1 "\t" $2 "\t" a[$1 FS $2] "\t" $3 }' "$1" "$2"
}

minus_noise() {
  awk -F'\t' 'NR == FNR { n[$1 FS $2] = 1; next } !(($1 FS $2) in n)' "$1" "$2"
}

snapshot() { ioreg -l -w0 2>/dev/null | redact > "$OUT/ioreg-$1.txt"; normalize "$OUT/ioreg-$1.txt" > "$WORK/$1.tsv"; }

write_helper() {
  cat > "$HELPER" <<'JS'
ObjC.import('Cocoa');
function run(argv) {
  $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/DisplayServices.framework').load;
  ObjC.bindFunction('DisplayServicesGetBrightness', ['int', ['unsigned int', 'float *']]);
  ObjC.bindFunction('DisplayServicesSetBrightness', ['int', ['unsigned int', 'float']]);
  ObjC.bindFunction('CGMainDisplayID', ['unsigned int', []]);
  ObjC.bindFunction('CGDisplayIsBuiltin', ['int', ['unsigned int']]);
  ObjC.bindFunction('CGSetDisplayTransferByFormula',
    ['int', ['unsigned int', 'float', 'float', 'float', 'float', 'float', 'float', 'float', 'float', 'float']]);
  ObjC.bindFunction('CGDisplayRestoreColorSyncSettings', ['void', []]);

  var id = $.CGMainDisplayID();
  var set = function (v) { return $.DisplayServicesSetBrightness(id, Math.min(1, Math.max(0, v))); };
  switch (argv[0]) {
    case 'info':
      return 'display=' + id + ' builtin=' + $.CGDisplayIsBuiltin(id);
    case 'get':
      var b = Ref();
      var r = $.DisplayServicesGetBrightness(id, b);
      return r === 0 ? String(b[0]) : 'ERR' + r;
    case 'set':
      return set(parseFloat(argv[1])) === 0 ? 'OK' : 'ERR';
    case 'ramp':
      var from = parseFloat(argv[1]), to = parseFloat(argv[2]), secs = parseFloat(argv[3]);
      var steps = Math.max(1, Math.round(secs * 60));
      for (var i = 1; i <= steps; i++) { set(from + (to - from) * i / steps); delay(secs / steps); }
      return 'OK';
    case 'gamma':
      var m = parseFloat(argv[1]);
      $.CGSetDisplayTransferByFormula(id, 0, m, 1, 0, m, 1, 0, m, 1);
      delay(parseFloat(argv[2]));
      $.CGDisplayRestoreColorSyncSettings();
      return 'OK';
    case 'restoregamma':
      $.CGDisplayRestoreColorSyncSettings();
      return 'OK';
  }
  return 'ERR unknown command';
}
JS
}

js() { osascript -l JavaScript "$HELPER" "$@" 2>/dev/null; }

AUTO=1

set_brightness() {
  if [ "$AUTO" = 1 ]; then
    js set "$1" >/dev/null
  else
    ask "$(t "   ✋ 请用亮度键把屏幕调到【$2】，调好按回车 " "   ✋ Use the brightness keys to set the screen to [$3], then press Return ")" >/dev/null
  fi
}

ORIGINAL=""
restore() {
  [ -n "${HELPER:-}" ] && [ -f "$HELPER" ] || return
  js restoregamma >/dev/null
  if [ "$AUTO" = 1 ] && [ -n "$ORIGINAL" ]; then
    js set "$ORIGINAL" >/dev/null
  fi
}

GAMMA_PID=""
cleanup() {
  [ -n "$GAMMA_PID" ] && kill "$GAMMA_PID" 2>/dev/null
  restore
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

STEP=0
step() {
  STEP=$((STEP + 1))
  tink
  say_bg "Step $STEP. $3"
  echo "$(ts)  $(t "第 $STEP 步" "Step $STEP")  $(t "$1" "$2")"
  echo "$(ts)  Step $STEP  $2" >> "$OUT/steps.log"
}

record_nits() {
  local value
  value="$(nits)"
  echo "$(ts)     $(t "真实亮度 $value 尼特" "brightness $value nits")${1:+  ($1)}"
  echo "$(ts)     brightness $value nits${1:+  ($1)}" >> "$OUT/steps.log"
}

WIPEMODE_URL="https://github.com/lidworks/wipemode/releases/latest/download/WipeMode.zip"
WIPEMODE_TEST=0

wipemode_touch_test() {
  local source="${WIPEMODE_ZIP:-$WIPEMODE_URL}" dir="$WORK/wipemode" logs="$HOME/Library/Logs/WipeMode/sessions.log"
  local had_logs=0 had_prefs=0 old_lines=0
  [ -f "$logs" ] && { had_logs=1; old_lines=$(wc -l < "$logs"); }
  defaults read app.lidworks.wipemode >/dev/null 2>&1 && had_prefs=1

  echo
  echo "▸ $(t "[附加] WipeMode 触摸测试" "[Bonus] WipeMode touch test")"
  mkdir -p "$dir"
  if [ -f "$source" ]; then
    cp "$source" "$dir/WipeMode.zip"
  elif ! curl -fsSL -o "$dir/WipeMode.zip" "$source"; then
    echo "   ⚠︎ $(t "下载失败（${source}），跳过" "Download failed ($source), skipping")"; return
  fi
  ditto -x -k "$dir/WipeMode.zip" "$dir" && [ -d "$dir/WipeMode.app" ] || { echo "   ⚠︎ $(t "解压失败，跳过" "Couldn't unzip, skipping")"; return; }
  open "$dir/WipeMode.app"
  if [ "$PROBE_LANG" = zh ]; then cat <<'EOF'
   1. 弹出欢迎框，点「Later」
   2. 按 ⌃⌥⌘W，弹出权限提示时点「Black Screen Only」
   3. 用手指在屏幕上乱点、乱滑：中间、四条边、灵动岛周围，也试试从边缘往里滑
   4. 盯着屏幕底部最后一行"Caught by screen: …"：数字跟着涨 = 触摸被接住了
      （退出后再看看背后有没有东西被点开、控制中心或通知中心有没有被拉出来）
   5. 同时按住左右 ⌘ 退出，或等 1 分钟自动退出
EOF
  else cat <<'EOF'
   1. When the welcome window appears, click "Later"
   2. Press ⌃⌥⌘W. When asked about permission, click "Black Screen Only"
   3. Tap and swipe all over the screen: the middle, all four edges, around the
      Dynamic Island, and swipes that start at an edge
   4. Watch the last line at the bottom ("Caught by screen: …"): if the numbers
      go up, your touches are being caught. After exiting, check that nothing
      behind it was opened and Control Center / Notification Center didn't appear
   5. Hold BOTH ⌘ keys to exit, or wait a minute for it to exit by itself
EOF
  fi
  if [ "$YES" = 1 ]; then sleep "${WIPEMODE_WAIT:-20}"; else ask "$(t "   测完按回车（会自动关掉并删除这份 WipeMode）" "   Press Return when done (this copy of WipeMode will be closed and deleted) ")" >/dev/null; fi

  pkill -f "$dir/WipeMode.app" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$dir/WipeMode.app" >/dev/null || break; sleep 0.3; done
  pkill -9 -f "$dir/WipeMode.app" 2>/dev/null

  [ -f "$logs" ] && tail -n +"$((old_lines + 1))" "$logs" > "$OUT/wipemode-sessions.log"
  rm -rf "$dir"
  [ "$had_logs" = 1 ] || rm -rf "$HOME/Library/Logs/WipeMode"
  if [ "$had_prefs" = 0 ]; then
    defaults delete app.lidworks.wipemode >/dev/null 2>&1
    rm -f "$HOME/Library/Preferences/app.lidworks.wipemode.plist"
  fi
  if [ -s "$OUT/wipemode-sessions.log" ]; then
    echo "   $(t "这次的记录（caught 里出现的就是落到黑屏上的触摸）：" "Recorded (anything under \"caught\" landed on the black screen):")"
    sed 's/^/     /' "$OUT/wipemode-sessions.log"
  else
    echo "   ⚠︎ $(t "没有记录：可能没进入擦屏，或者还没退出就按了回车" "Nothing recorded: Wipe Mode may not have started")"
  fi
  echo "   ✓ $(t "这份 WipeMode 已关闭并删除" "This copy of WipeMode has been closed and deleted")"
}

main() {
  for arg in "$@"; do
    case "$arg" in
      --yes|-y) YES=1 ;;
      --wipemode) WIPEMODE_TEST=1 ;;
    esac
  done
  STAMP="$(date +%Y%m%d-%H%M%S)"
  OUT="${PROBE_OUT_DIR:-$HOME/Desktop}/logo-probe-$STAMP"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/logo-probe.XXXXXX")" || { echo "✗ $(t "建不了临时文件夹" "Couldn't create a temporary folder")"; exit 1; }
  HELPER="$WORK/helper.js"
  mkdir -p "$OUT" || { echo "✗ $(t "建不了结果文件夹：" "Couldn't create the results folder: ")$OUT"; exit 1; }
  trap cleanup EXIT
  trap 'echo; echo "$(t "中止，正在恢复…" "Stopped. Restoring your settings…")"; exit 130' INT TERM
  write_helper

  if [ "$PROBE_LANG" = zh ]; then cat <<'EOF'

  ┌─────────────────────────────────────────────────┐
  │   Lidworks 发光 logo 探测   ·   约 3 分钟        │
  │   屏幕会变亮变暗，还会有 6 秒几乎全黑            │
  │   跑完自动恢复；Ctrl-C 随时中止并恢复            │
  └─────────────────────────────────────────────────┘

EOF
  else cat <<'EOF'

  ┌──────────────────────────────────────────────────────────┐
  │   Lidworks logo probe   ·   about 3 minutes                │
  │   Your screen will get brighter and dimmer, and go         │
  │   almost black for 6 seconds. Everything is restored at    │
  │   the end. Press Ctrl-C any time to stop and restore.      │
  └──────────────────────────────────────────────────────────┘

EOF
  fi

  echo "▸ [1/4] $(t "收集硬件信息…" "Listing hardware…")"
  {
    echo "== Time =="; date
    echo; echo "== System =="; sw_vers
    echo; echo "== Model =="; sysctl -n hw.model; sysctl -n machdep.cpu.brand_string
    echo; echo "== Display =="; js info
  } > "$OUT/system.txt" 2>&1
  system_profiler SPHardwareDataType SPDisplaysDataType 2>/dev/null | redact > "$OUT/system-profiler.txt"
  hidutil list 2>&1 | redact > "$OUT/hidutil-list.txt"
  hidutil list --matching '{"PrimaryUsagePage":13}' 2>&1 | redact > "$OUT/hidutil-digitizers.txt"
  ioreg -l -w0 2>/dev/null | redact > "$OUT/ioreg-full.txt"

  {
    echo "== Property names with keywords (count) =="
    grep -oiE '"[^"]*(logo|glow|halo|emblem|indicator|lumin|illum|backlight|nits|apple-?light)[^"]*"' "$OUT/ioreg-full.txt" | sort | uniq -c | sort -rn
    grep -oE '"[^"]*(LED|[-_]led|led[-_])[^"]*"' "$OUT/ioreg-full.txt" | sort | uniq -c | sort -rn
    echo
    echo "== Suspicious device nodes =="
    grep -E '\+-o ' "$OUT/ioreg-full.txt" | grep -iE 'logo|glow|led|light|lumin|indicator|pwm|backlight|emblem' | sed -E 's/^[ |]*\+-o //; s/, registered.*//'
    echo
    echo "== Suspicious HID devices =="
    grep -iE 'logo|led|light|lumin|indicator|backlight|als|ambient' "$OUT/hidutil-list.txt"
  } > "$OUT/keywords.txt" 2>&1
  echo "   ✓ $(t "设备列表已保存（$(grep -c '+-o ' "$OUT/ioreg-full.txt") 个 IORegistry 节点）" "Hardware list saved ($(grep -c '+-o ' "$OUT/ioreg-full.txt") IORegistry nodes)")"

  ORIGINAL="$(js get)"
  case "$ORIGINAL" in
    ''|ERR*)
      AUTO=0
      ORIGINAL=""
      echo "   ⚠︎ $(t "脚本没法自动改亮度，接下来会提示你手动按亮度键" "Can't change brightness automatically; you'll be asked to use the brightness keys")"
      ;;
    *)
      local percent
      percent="$(awk -v v="$ORIGINAL" 'BEGIN { printf "%.0f%%", v * 100 }')"
      echo "   ✓ $(t "当前亮度滑块 ${percent}，真实亮度 $(nits) 尼特" "Brightness slider at $percent, actual $(nits) nits")"
      ;;
  esac
  echo "original_slider=$ORIGINAL auto=$AUTO" >> "$OUT/system.txt"

  echo
  if [ "$PROBE_LANG" = zh ]; then cat <<'EOF'
▸ [2/4] 准备录像（可选，但非常有用）
   1. 手机绕到屏幕背面，对准发光 logo，【开始录像，要录声音】
      （每一步电脑都会"叮"一声并用英文报步骤号，回头看视频就能对上）
   2. 尽量让手机固定不动
EOF
  else cat <<'EOF'
▸ [2/4] Get ready to film (optional, but super helpful)
   1. Point your phone at the glowing logo on the back of the lid and START
      RECORDING WITH SOUND. Each step plays a chime and announces its number,
      so the video lines up with the log.
   2. Keep the phone as still as you can.
EOF
  fi
  ask "$(t "   准备好了按回车 " "   Press Return when ready ")" >/dev/null
  for n in 3 2 1; do echo "   $n"; say_bg "$n"; sleep 1; done

  echo
  echo "▸ [3/4] $(t "改亮度，请盯着 logo（每步约 4 秒）" "Changing brightness. Watch the logo (about 4 s per step)")"
  echo "time      step" > "$OUT/steps.log"

  step "亮度 100%" "Brightness 100%" "Maximum brightness."
  set_brightness 1 "最亮" "maximum"
  sleep 1.5; record_nits; snapshot max-a; sleep 1

  step "亮度 100%（再拍一次快照，用来过滤本来就在变的属性）" "Brightness 100% (second snapshot, to filter out noise)" "Still maximum."
  sleep 1.5; snapshot max-b; sleep 0.5

  step "亮度 0%：logo 会不会完全熄灭？" "Brightness 0%: does the logo turn fully off?" "Minimum brightness."
  set_brightness 0 "最暗" "minimum"
  sleep 1.5; record_nits; snapshot min; sleep 1.5

  step "亮度 50%" "Brightness 50%" "Half brightness."
  set_brightness 0.5 "一半" "half"
  sleep 1.5; record_nits; sleep 2

  step "亮度 100%" "Brightness 100%" "Maximum again."
  set_brightness 1 "最亮" "maximum"
  sleep 1.5; record_nits; snapshot max-c; sleep 1

  if [ "$AUTO" = 1 ]; then
    step "3 秒内从 100% 平滑降到 0%：logo 是平滑变化还是一跳一跳？" "Smooth fade 100% → 0% over 3 s: smooth or stepped?" "Smooth fade down."
    js ramp 1 0 3 >/dev/null; record_nits
    step "3 秒内从 0% 平滑升到 100%" "Smooth fade 0% → 100% over 3 s" "Smooth fade up."
    js ramp 0 1 3 >/dev/null; sleep 1; record_nits
  fi

  step "★ 关键：亮度保持 100%，用 gamma 把画面压到接近全黑 6 秒。logo 还亮着吗？" \
       "★ Key test: brightness stays at 100% but the picture goes almost black for 6 s. Is the logo still lit?" \
       "Key test. Screen goes dark. Watch the logo."
  set_brightness 1 "最亮" "maximum"
  sleep 1
  js gamma 0.2 6 >/dev/null &
  GAMMA_PID=$!
  sleep 2; record_nits "picture darkened"; snapshot gamma-dark
  wait "$GAMMA_PID"
  GAMMA_PID=""
  record_nits "picture restored"
  snapshot gamma-after

  step "结束，恢复原来的亮度" "Done, restoring your brightness" "Done. You can stop recording."
  restore
  sleep 1; record_nits "after restore"

  if [ "$WIPEMODE_TEST" = 1 ] || [ "$(ask "$(t "   要顺便测 WipeMode 能不能挡住触摸吗？（只在触屏 Mac 上有意义，约 1 分钟）[y/N] " "   Also test whether WipeMode blocks touches? (touchscreen Macs only, ~1 min) [y/N] ")" n)" = "y" ]; then
    wipemode_touch_test
  fi

  echo
  echo "▸ [4/4] $(t "分析" "Analyzing")"
  changed "$WORK/max-a.tsv" "$WORK/max-b.tsv" > "$WORK/noise.tsv"
  changed "$WORK/max-a.tsv" "$WORK/max-c.tsv" >> "$WORK/noise.tsv"
  changed "$WORK/max-a.tsv" "$WORK/min.tsv" > "$WORK/bright.tsv"
  cp "$WORK/noise.tsv" "$WORK/gamma-noise.tsv"
  changed "$WORK/max-c.tsv" "$WORK/gamma-after.tsv" >> "$WORK/gamma-noise.tsv"
  changed "$WORK/max-c.tsv" "$WORK/gamma-dark.tsv" > "$WORK/gamma.tsv"
  {
    echo "# Properties that follow the brightness setting and return to their value at 100% (most likely related to brightness control)"
    echo "# node | property | at 100% | at 0%"
    minus_noise "$WORK/noise.tsv" "$WORK/bright.tsv" | cut -c1-400
    echo
    echo "# -- For reference: everything that differed between 100% and 0% (includes time-based noise) --"
    cut -c1-400 "$WORK/bright.tsv"
  } > "$OUT/changes-with-brightness.tsv"
  {
    echo "# Properties that changed only when the picture was darkened (brightness setting unchanged) and came back afterwards"
    echo "# node | property | normal | darkened"
    minus_noise "$WORK/gamma-noise.tsv" "$WORK/gamma.tsv" | cut -c1-400
  } > "$OUT/changes-with-gamma.tsv"
  rm -f "$OUT"/ioreg-max-b.txt "$OUT"/ioreg-max-c.txt "$OUT"/ioreg-gamma-after.txt

  local strong
  strong="$(minus_noise "$WORK/noise.tsv" "$WORK/bright.tsv")"
  echo "   $(t "随亮度变化的属性：$(printf '%s' "$strong" | grep -c .) 个（前 15 个）：" "Properties that follow brightness: $(printf '%s' "$strong" | grep -c .) (first 15):")"
  printf '%s\n' "$strong" | head -15 | awk -F'\t' 'NF { printf "     %-40s %-36s %s → %s\n", substr($1,1,40), substr($2,1,36), substr($3,1,20), substr($4,1,20) }'
  echo "   $(t "只压暗画面时变化的属性：" "Properties that changed with the picture only: ")$(($(grep -c . "$OUT/changes-with-gamma.tsv") - 2))"
  echo "   $(t "关键词命中（前 10 个）：" "Keyword hits (first 10):")"
  sed -n '2,11p' "$OUT/keywords.txt" | sed 's/^/     /'

  local zip="$OUT.zip"
  (cd "$(dirname "$OUT")" && zip -qr "$zip" "$(basename "$OUT")") && rm -rf "$OUT"
  echo
  echo "✓ $(t "完成。结果：" "Done. Results: ")$zip"
  if [ "$PROBE_LANG" = zh ]; then cat <<EOF
   如果你是来帮忙测试的：请把这个 zip（还有录的视频）发到 ${CONTACT}，或在 X 上私信 ${CONTACT_X}。谢谢！
   结果里没有序列号、用户名之类能认出你或这台电脑的信息。

EOF
  else cat <<EOF
   Please send this zip (and your video, if you filmed one) to $CONTACT,
   or DM $CONTACT_X on X. Thank you so much!
   It contains no serial numbers, user names or anything that identifies you or this Mac.

EOF
  fi
  [ "$YES" = 1 ] || open -R "$zip" 2>/dev/null
  local answer
  answer="$(ask "$(t "   直接回车保留结果；在展示机上的话，隔空投送给自己后输入 d 再回车删除：" "   Press Return to keep the results, or type d and Return to delete them from this Mac: ")" "")"
  if [ "$answer" = "d" ]; then
    rm -rf "$OUT" "$zip"
    echo "   $(t "已删除，没有留下任何文件。" "Deleted. Nothing was left behind.")"
  fi
}

if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
