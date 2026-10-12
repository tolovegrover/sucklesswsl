#!/usr/bin/env bash
#
# sucklesswsl — a tiling-WM session for WSL (i3 or dwm)
#
# The session is one window. Apps launched inside it tile inside that window.
# While the window is focused, VcXsrv's keyboard hook takes the shortcuts
# Windows would otherwise steal (the Windows key, Alt+Tab, Alt+F4, Alt+Space)
# and hands them to the WM. Alt+Enter opens a terminal. Alt+2 switches
# workspace. Click another window, or press Alt+Shift+z, and the hook drops
# so Windows shortcuts work again.
#
# It changes nothing about your WSL/WSLg setup: no .wslconfig, no shell rc,
# no system i3/dwm config. Other GUI apps keep using WSLg.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
I3_CONFIG="${I3_CONFIG:-$HERE/i3.config}"
CONTROL="$HERE/session-control.py"
HOST_PS1="$HERE/host-window.ps1"
PIDFILE="/tmp/sucklesswsl.pid"
MINIMIZE="/tmp/sucklesswsl-minimize"

# Find a python3 that can import tkinter (for the floating exit button).
find_python() {
  local p
  for p in /usr/bin/python3 python3; do
    command -v "$p" >/dev/null 2>&1 || continue
    "$p" -c "import tkinter" >/dev/null 2>&1 && { echo "$p"; return 0; }
  done
  return 1
}

find_vcxsrv() {
  local c
  for c in \
    "/mnt/c/Program Files/VcXsrv/vcxsrv.exe" \
    "/mnt/c/Program Files (x86)/VcXsrv/vcxsrv.exe"
  do
    [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Windows host address as seen from this WSL VM (the default gateway).
windows_host() {
  ip -4 route show default 2>/dev/null | awk '{print $3; exit}'
}

# True (exit 0) when something accepts TCP on host:port.
port_open() {
  python3 -c 'import socket,sys
s=socket.socket(); s.settimeout(0.3)
r=s.connect_ex((sys.argv[1], int(sys.argv[2])))
s.close(); sys.exit(0 if r==0 else 1)' "$1" "$2"
}

# True when an X server completes the connection handshake.
x_ready() {
  python3 -c 'import socket,sys
s=socket.create_connection((sys.argv[1], int(sys.argv[2])), 1)
s.sendall(bytes([ord("l"), 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
ok = s.recv(1) == b"\x01"
s.close(); sys.exit(0 if ok else 1)' "$1" "$2"
}

vcxsrv_pids() {
  tasklist.exe /FI "IMAGENAME eq vcxsrv.exe" /FO CSV /NH 2>/dev/null \
    | tr -d '\r' \
    | awk -F',' 'tolower($1) ~ /vcxsrv/ { gsub(/"/, "", $2); if ($2 ~ /^[0-9]+$/) print $2 }'
}

# ---- options --------------------------------------------------------------
MODE="fullscreen"
SIZE="1600x900"
WM="${WM:-i3}"

usage() {
  cat <<EOF
Usage: ./startwm.sh [--wm=i3|dwm] [--fullscreen | --windowed | --size=WxH]

  --wm=i3|dwm    which window manager to run (default i3)
  --fullscreen   session fills the screen (default)
  --windowed     open as a resizable window (default size $SIZE)
  --size=WxH     windowed at the given size, e.g. --size=1920x1080
  -h, --help     show this help

While the session window is focused, Windows shortcuts are handed to the WM.
Alt+Shift+z minimizes it and gives those shortcuts back to Windows.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --wm=*)       WM="${arg#*=}" ;;
    --fullscreen) MODE="fullscreen" ;;
    --windowed)   MODE="windowed" ;;
    --size=*)     MODE="windowed"; SIZE="${arg#*=}" ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

case "$WM" in
  i3|dwm) ;;
  *) echo "ERROR: --wm must be 'i3' or 'dwm' (got '$WM')" >&2; exit 1 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required." >&2; exit 1; }

if [ "$WM" = "i3" ]; then
  command -v i3 >/dev/null 2>&1 || { echo "ERROR: i3 not found. Run ./install-deps.sh first." >&2; exit 1; }
  [ -f "$I3_CONFIG" ] || { echo "ERROR: i3 config not found at $I3_CONFIG" >&2; exit 1; }
else
  [ -x "$HERE/dwm/dwm" ] || { echo "ERROR: dwm not built at $HERE/dwm/dwm. Run ./install-deps.sh first." >&2; exit 1; }
fi

# Clients must use the session's X server, not WSLg's Wayland display,
# or they pop out as separate Windows windows.
unset WAYLAND_DISPLAY
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export SDL_VIDEODRIVER=x11
export MOZ_ENABLE_WAYLAND=0
export KITTY_DISABLE_WAYLAND=1

WIN_PID=""
WIN_PS1=""
XEPHYR_PID=""
CONTROL_PID=""
CLEANED=0
STARTED=0

cleanup() {
  [ "$CLEANED" = 1 ] && return
  CLEANED=1
  # The keyboard hook lives inside VcXsrv. Kill that first so Windows
  # shortcuts return the moment the session ends, before anything else.
  if [ -n "$WIN_PID" ]; then
    taskkill.exe /PID "$WIN_PID" /F >/dev/null 2>&1 || true
    WIN_PID=""
  fi
  if [ -n "$XEPHYR_PID" ]; then
    kill "$XEPHYR_PID" 2>/dev/null || true
    XEPHYR_PID=""
  fi
  if [ -n "${WM_PID:-}" ]; then
    kill "$WM_PID" 2>/dev/null || true
  fi
  if [ -n "$CONTROL_PID" ]; then
    kill "$CONTROL_PID" 2>/dev/null || true
  fi
  rm -f "$PIDFILE" "$MINIMIZE"
  if [ "$STARTED" = 1 ]; then
    echo ">> Session closed. Windows shortcuts are back. WSL itself is unchanged."
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Alt+Shift+z (and the on-screen Minimize button) signal this shell.
minimize_host() {
  if [ -n "$WIN_PID" ] && [ -n "$WIN_PS1" ]; then
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden \
      -File "$WIN_PS1" -ProcessId "$WIN_PID" >/dev/null 2>&1 || true
  fi
  return 0
}
trap minimize_host USR1

# The WM execs this file. The pid is baked in so the i3 config needs no "$".
write_minimize_helper() {
  cat >"$MINIMIZE" <<EOF
#!/bin/sh
kill -USR1 $$ 2>/dev/null || true
EOF
  chmod +x "$MINIMIZE"
}

echo $$ >"$PIDFILE"
write_minimize_helper

# ---- start the X server ---------------------------------------------------
VCXSRV=""
if VCXSRV="$(find_vcxsrv)"; then
  HOST_IP="$(windows_host)"
  [ -n "$HOST_IP" ] || { echo "ERROR: no route to the Windows host." >&2; exit 1; }

  N=1
  while port_open "$HOST_IP" $((6000 + N)); do
    N=$((N + 1))
    [ "$N" -le 30 ] || { echo "ERROR: no free X display on $HOST_IP." >&2; exit 1; }
  done
  SESSION_DISPLAY="${HOST_IP}:$N.0"

  WIN_TEMP="$(cmd.exe /d /c "echo %TEMP%" 2>/dev/null | tr -d '\r\n')"
  LOGFILE="${WIN_TEMP}\\sucklesswsl-vcxsrv.log"
  LOG_UNIX="$(wslpath -u "$WIN_TEMP")/sucklesswsl-vcxsrv.log"
  WIN_PS1="${WIN_TEMP}\\sucklesswsl-host-window.ps1"
  cp "$HOST_PS1" "$(wslpath -u "$WIN_TEMP")/sucklesswsl-host-window.ps1"
  rm -f "$LOG_UNIX"

  # -lesspointer hides the Windows cursor. VcXsrv rejects it together with
  # -fullscreen ("invalid with -scrollbars, -resize, -nodecoration, or -lesspointer").
  # Fullscreen uses the primary monitor's current mode, in real pixels, and
  # that monitor's scale as the X dpi. Without the DPI override Windows hands
  # over the scaled-down size and stretches it.
  NATIVE="$(powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden \
    -File "$WIN_PS1" -Native -ExePath "$(wslpath -w "$VCXSRV")" 2>/dev/null | tr -d '\r')"
  NATIVE_GEO="${NATIVE%% *}"
  NATIVE_DPI="${NATIVE##* }"
  [[ "$NATIVE_GEO" =~ ^[0-9]+x[0-9]+$ ]] || NATIVE_GEO=""
  [[ "$NATIVE_DPI" =~ ^[0-9]+$ ]] || NATIVE_DPI=""

  ARGS=(
    ":$N"
    -br -ac -keyhook -nowinkill -noprimary
    -listen tcp -silent-dup-error
    -logfile "$LOGFILE" -logverbose 2
  )
  if [ "$MODE" = "fullscreen" ]; then
    ARGS+=(-fullscreen)
    [ -n "$NATIVE_GEO" ] && ARGS+=(-screen 0 "$NATIVE_GEO")
    [ -n "$NATIVE_DPI" ] && ARGS+=(-dpi "$NATIVE_DPI")
  else
    ARGS+=(-lesspointer -screen 0 "$SIZE")
    [ -n "$NATIVE_DPI" ] && ARGS+=(-dpi "$NATIVE_DPI")
  fi

  echo ">> Starting $WM"
  echo "   display server: VcXsrv (keyboard hook on while this window is focused)"
  echo "   session display: $SESSION_DISPLAY"
  echo "   your WSLg apps : unchanged"
  if [ "$MODE" = "windowed" ]; then
    echo "   mode           : windowed ($SIZE)"
  else
    echo "   mode           : fullscreen${NATIVE_GEO:+ $NATIVE_GEO}${NATIVE_DPI:+ at ${NATIVE_DPI} dpi}"
  fi
  echo "   hand keys back : Alt+Shift+z minimizes. ⏻ Exit quits. Alt+Shift+e asks first."

  BEFORE="$(vcxsrv_pids | sort)"
  "$VCXSRV" "${ARGS[@]}" >/dev/null 2>&1 &

  ready=0
  for _ in $(seq 1 30); do
    if [ -f "$LOG_UNIX" ] && grep -q "Fatal server error" "$LOG_UNIX"; then
      echo "ERROR: VcXsrv refused to start." >&2
      grep -E "winValidateArgs|Fatal server error|\\(EE\\)" "$LOG_UNIX" >&2 || true
      exit 1
    fi
    if x_ready "$HOST_IP" $((6000 + N)); then ready=1; break; fi
    sleep 0.2
  done
  [ "$ready" = 1 ] || {
    echo "ERROR: could not connect to VcXsrv at $SESSION_DISPLAY." >&2
    echo "       If Windows Firewall asked, allow VcXsrv on private networks and run this again." >&2
    [ -f "$LOG_UNIX" ] && tail -20 "$LOG_UNIX" >&2 || true
    exit 1
  }

  NOW="$(vcxsrv_pids | sort)"
  WIN_PID="$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$NOW") | head -1 || true)"
  [ -n "$WIN_PID" ] || { echo "ERROR: VcXsrv is up but its process id could not be found." >&2; exit 1; }
  STARTED=1
else
  echo "WARNING: VcXsrv not found. Falling back to Xephyr on WSLg." >&2
  echo "         Windows will still steal Alt+Tab, Alt+F4 and the Windows key." >&2
  echo "         Install VcXsrv, then run this again, for the native keybindings." >&2
  command -v Xephyr >/dev/null 2>&1 || { echo "ERROR: Xephyr not found either. Run ./install-deps.sh." >&2; exit 1; }
  [ -n "${DISPLAY:-}" ] || { echo "ERROR: no host DISPLAY set — is WSLg running?" >&2; exit 1; }

  N=1
  while [ -e "/tmp/.X11-unix/X$N" ]; do N=$((N + 1)); done
  SESSION_DISPLAY=":$N"
  HOST_DISPLAY="$DISPLAY"

  if [ "$MODE" = "fullscreen" ]; then
    GEO=(-fullscreen)
  else
    GEO=(-screen "$SIZE")
  fi

  echo ">> Starting $WM (Xephyr fallback)"
  echo "   session display: $SESSION_DISPLAY"
  DISPLAY="$HOST_DISPLAY" Xephyr \
    -title "sucklesswsl — $WM" \
    -resizeable -ac -br -noreset \
    "${GEO[@]}" "$SESSION_DISPLAY" &
  XEPHYR_PID=$!

  for _ in $(seq 1 50); do
    [ -e "/tmp/.X11-unix/X$N" ] && break
    kill -0 "$XEPHYR_PID" 2>/dev/null || { echo "ERROR: Xephyr exited early." >&2; exit 1; }
    sleep 0.1
  done
  STARTED=1
fi

export DISPLAY="$SESSION_DISPLAY"

# Cheat sheet on the root window, visible on an empty workspace.
# Best-effort: a missing Pillow install must not stop the session.
for _py in /usr/bin/python3 python3; do
  command -v "$_py" >/dev/null 2>&1 || continue
  "$_py" -c "import PIL" >/dev/null 2>&1 || continue
  "$_py" "$HERE/wallpaper.py" --wm "$WM" \
    || echo "   note: cheat-sheet wallpaper skipped" >&2
  break
done

if PYTHON="$(find_python)"; then
  "$PYTHON" "$CONTROL" --session-pid "$$" &
  CONTROL_PID=$!
else
  echo "   note: no python3+tkinter — on-screen button skipped" >&2
fi

if [ "$WM" = "i3" ]; then
  i3 -c "$I3_CONFIG" &
else
  "$HERE/dwm/dwm" &
fi
WM_PID=$!

# wait is a shell builtin, so Alt+Shift+z (SIGUSR1) runs the trap immediately
# and then we go back to waiting. A real WM exit ends the loop.
while kill -0 "$WM_PID" 2>/dev/null; do
  wait "$WM_PID" || true
done
