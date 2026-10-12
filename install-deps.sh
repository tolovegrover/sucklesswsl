#!/usr/bin/env bash
#
# install-deps.sh — one-time setup for sucklesswsl.
#
# This is the ONLY step that touches the system (installs packages via pacman).
# Everything it installs is inert until you run ./startwm.sh. It does NOT modify
# any WSL/WSLg settings, shell rc files, or i3/dwm system configuration.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DWM_VERSION="6.5"
DWM_DIR="$HERE/dwm"

echo "==> Installing packages (Xephyr, dmenu, build tools, X libs)"
echo "    You'll be prompted for your sudo password."
sudo pacman -S --needed --noconfirm \
  xorg-server-xephyr \
  dmenu \
  tk \
  base-devel \
  libx11 \
  libxft \
  libxinerama \
  xorg-xeyes        # small GUI app, handy for testing the nested session
# tk provides libtk so /usr/bin/python3's tkinter works (floating exit button).

#-----------------------------------------------------------------------------
# Build dwm locally (NOT installed system-wide — binary stays in ./dwm/dwm)
#-----------------------------------------------------------------------------
if [ -x "$DWM_DIR/dwm" ]; then
  echo "==> dwm already built at $DWM_DIR/dwm — skipping (delete ./dwm to rebuild)"
else
  echo "==> Fetching dwm source"
  if [ ! -d "$DWM_DIR" ]; then
    if command -v git >/dev/null 2>&1 && \
       git clone --depth 1 https://git.suckless.org/dwm "$DWM_DIR" 2>/dev/null; then
      echo "    cloned from git.suckless.org"
    else
      echo "    git unavailable/failed; downloading release tarball"
      tmp="$(mktemp -d)"
      curl -fsSL "https://dl.suckless.org/dwm/dwm-${DWM_VERSION}.tar.gz" \
        -o "$tmp/dwm.tar.gz"
      mkdir -p "$DWM_DIR"
      tar -xzf "$tmp/dwm.tar.gz" -C "$DWM_DIR" --strip-components=1
      rm -rf "$tmp"
    fi
  fi

  echo "==> Patching dwm config for this system"
  # 1) Create config.h from the default so we can customise it.
  [ -f "$DWM_DIR/config.h" ] || cp "$DWM_DIR/config.def.h" "$DWM_DIR/config.h"
  # 2) Use kitty as the terminal (stock dwm uses 'st', which isn't installed).
  #    MODKEY stays Mod1Mask (Alt) — the dwm default — exactly what we want.
  sed -i 's/"st", NULL/"kitty", NULL/' "$DWM_DIR/config.h"
  #    Alt+Shift+z minimizes the session window (startwm.sh writes the helper).
  if ! grep -q '/tmp/sucklesswsl-minimize' "$DWM_DIR/config.h"; then
    sed -i '/static const char \*termcmd\[\]/a static const char *mincmd[]   = { "/tmp/sucklesswsl-minimize", NULL };' "$DWM_DIR/config.h"
    sed -i '/{ MODKEY|ShiftMask,[[:space:]]*XK_q,[[:space:]]*quit,/i { MODKEY|ShiftMask,             XK_z,      spawn,          {.v = mincmd } },' "$DWM_DIR/config.h"
  fi
  # 3) Fix X11 lib/include paths for Arch (default config.mk points at
  #    /usr/X11R6, which doesn't exist here).
  sed -i \
    -e 's#^X11INC = .*#X11INC = /usr/include#' \
    -e 's#^X11LIB = .*#X11LIB = /usr/lib#' \
    "$DWM_DIR/config.mk"

  echo "==> Building dwm"
  make -C "$DWM_DIR" clean >/dev/null 2>&1 || true
  make -C "$DWM_DIR"
  echo "    built: $DWM_DIR/dwm"
fi

echo
echo "==> Done. Verify with:"
echo "    command -v Xephyr dmenu kitty && ls -l $DWM_DIR/dwm"
echo
echo "    Launch i3 session:  ./startwm.sh"
echo "    Launch dwm session: ./startwm.sh --wm=dwm"
