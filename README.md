# sucklesswsl

A self-contained tiling-WM session for **WSL** (Arch). It runs **i3** or **dwm**
inside a single window. Applications you launch from inside the session tile
*inside that window* — like a real dwm/i3 desktop — instead of popping out as
separate Windows windows.

The window is a [VcXsrv](https://sourceforge.net/projects/vcxsrv/) X server with
its keyboard hook on. While that window is focused, the shortcuts Windows would
steal (the Windows key, Alt+Tab, Alt+F4, Alt+Space) are delivered to the WM
instead. **Alt+Enter** opens a terminal. **Alt+2** switches to workspace 2.
Focus something else, or press **Alt+Shift+z**, and Windows has its shortcuts back.
One click on **⏻ Exit** quits at once. **Alt+Shift+e** asks first, because
that chord is easy to hit by mistake. Either way the hook is gone as soon as
the session ends: Windows shortcuts work again, with nothing left disabled.

## It does **not** touch your WSL setup

This is the whole point. When the launcher isn't running, your WSL behaves
exactly as before:

- The nested session uses a **fresh, unused display** (`:1`, `:2`, …). Your real
  display (`:0` / WSLg) is never reconfigured.
- i3 reads an **isolated config** (`i3.config`) passed via `i3 -c`. Your default
  `~/.config/i3/config` is never read or written.
- dwm is **built and run from `./dwm/`** — never installed system-wide.
- No `.bashrc`, environment variables, `/etc/wsl.conf`, or WSLg files are
  modified.
- **`rm -rf` this folder = full uninstall** (plus optionally removing the
  packages below).

Normal WSL GUI usage is unaffected: outside the session, apps still open as
Windows windows via WSLg on `DISPLAY=:0`.

## Setup (once)

```bash
./install-deps.sh
```

This installs `xorg-server-xephyr`, `dmenu`, build tools and X libraries
(`base-devel`, `libx11`, `libxft`, `libxinerama`), plus `xorg-xeyes` as a test
app, then compiles dwm into `./dwm/dwm`. It will ask for your sudo password.
Installing the packages is the only system-wide change, and they stay inert
until you actually run `startwm.sh`.

The keyboard hook needs **VcXsrv** on Windows
([vcxsrv](https://sourceforge.net/projects/vcxsrv/)). The launcher looks in
`C:\Program Files\VcXsrv` and `C:\Program Files (x86)\VcXsrv`. Without it,
the session falls back to Xephyr on WSLg, and Windows keeps Alt+Tab, Alt+F4
and the Windows key.

## Usage

```bash
./startwm.sh                      # i3, fullscreen (default)
./startwm.sh --wm=dwm             # dwm, fullscreen
./startwm.sh --windowed           # i3 in a resizable 1600x900 window
./startwm.sh --windowed --size=1920x1080
./startwm.sh --wm=dwm --size=1280x800
./startwm.sh --help
```

Fullscreen uses the **primary monitor's real pixels**, whatever that mode is,
and that monitor's Windows scale as the X dpi (100% → 96, 125% → 120,
150% → 144, 200% → 192). Before VcXsrv starts, the launcher sets a per-user
compatibility flag on `vcxsrv.exe` only (`HIGHDPIAWARE` in
`HKCU\...\AppCompatFlags\Layers`) so Windows does not stretch a smaller
bitmap over the screen. Nothing about the resolution is hardcoded, and the
flag is not a machine-wide setting.

A window opens running your chosen WM. Launch a terminal, then more apps —
they tile inside the window. Quit the WM and the window closes automatically.

### Windows shortcuts, only while the session is focused

VcXsrv installs its keyboard hook when the session window gains focus, and
removes it when the window loses focus. Focused, those keys belong to i3/dwm.
Unfocused, they belong to Windows.

To give them back without quitting, **Alt+Shift+z** minimizes the session.
Click the taskbar icon to focus it again. The hook comes back with the focus.

### Exit button

A small **always-on-top `⏻ Exit` button** sits in the **top-right corner**.
One click ends the session. There is no second question.

## Keybindings

The modifier is **Alt** (`Mod1`) for both WMs, which is i3's own default.
The same sheet is the wallpaper: an empty workspace shows it.

### i3

| Keys | Action |
|------|--------|
| `Alt+Return` | open terminal (kitty) |
| `Alt+d` | app launcher (dmenu) |
| `Alt+Shift+q` | close focused window |
| `Alt+h/j/k/l` or arrows | move focus |
| `Alt+Shift+h/j/k/l` | move window |
| `Alt+1..9` | switch workspace |
| `Alt+Shift+1..9` | send window to workspace |
| `Alt+f` | toggle fullscreen |
| `Alt+b` / `Alt+v` | split horizontal / vertical |
| `Alt+w` / `Alt+s` / `Alt+e` | tabbed / stacking / toggle split |
| `Alt+r` | resize mode (arrows/hjkl, `Enter` to exit) |
| `Alt+Shift+z` | **minimize** (Windows shortcuts work again) |
| `Alt+Shift+e` | **exit session** (asks first; the corner button does not) |

### dwm (stock suckless bindings)

| Keys | Action |
|------|--------|
| `Alt+Shift+Return` | open terminal (kitty) |
| `Alt+p` | app launcher (dmenu) |
| `Alt+Shift+c` | close focused window |
| `Alt+j` / `Alt+k` | focus next / previous |
| `Alt+1..9` | switch tag (workspace) |
| `Alt+Shift+1..9` | send window to tag |
| `Alt+t` / `Alt+m` / `Alt+f` | tiled / monocle / floating layout |
| `Alt+Return` | promote window to master |
| `Alt+Shift+z` | **minimize** (Windows shortcuts work again) |
| `Alt+Shift+q` | **exit session** (closes the window) |

## How it works

```
Windows keyboard
    │
    └── VcXsrv window, hook on only while it is focused
            │
            └── i3 / dwm
                    ├── kitty, dmenu, other apps  ← tiled inside
                    └── ⏻ floating button         ← always on top

WSLg stays as it is. Apps you launch outside the session still open
as normal Windows windows.
```

`startwm.sh` starts VcXsrv on a free display, runs the WM against it, and
kills VcXsrv when the WM exits. If VcXsrv is not installed it falls back to
a Xephyr window on WSLg, without the keyboard hook.

## Uninstall

```bash
rm -rf sucklesswsl          # the project folder; removes everything it added
# optional, if you don't want the packages anymore:
sudo pacman -Rns xorg-server-xephyr dmenu tk xorg-xeyes
```

The per-user VcXsrv DPI flag, if you want it gone too:

```powershell
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name 'C:\Program Files\VcXsrv\vcxsrv.exe'
```
