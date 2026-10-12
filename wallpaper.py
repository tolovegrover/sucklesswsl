#!/usr/bin/env python3
"""Draw the session cheat sheet and set it as the X root wallpaper.

Run with DISPLAY pointing at the session (startwm.sh does this).
  wallpaper.py --wm i3
  wallpaper.py --wm dwm
  wallpaper.py --preview out.png --size 1920x1080 --wm i3
"""
import argparse
import ctypes
import sys

from PIL import Image, ImageDraw, ImageFont

BG = (18, 20, 26)
CARD = (31, 36, 48)
CARD_EDGE = (54, 62, 82)
HEAD = (230, 230, 230)
MUTED = (154, 162, 178)
KEY_BG = (42, 48, 64)
KEY_EDGE = (90, 102, 128)
KEY_FG = (244, 220, 160)
TITLE = (230, 230, 230)
RULE = (58, 66, 86)

FONT_SANS = "/usr/share/fonts/TTF/DejaVuSans.ttf"
FONT_SANS_BOLD = "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"
FONT_MONO = "/usr/share/fonts/TTF/DejaVuSansMono.ttf"
FONT_MONO_BOLD = "/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf"

# (column groups of (heading, [(keys, what), ...]))
I3 = [
    [
        ("Launch", [
            ("Alt+Enter", "open terminal"),
            ("Alt+d", "app launcher"),
            ("Alt+Shift+q", "close window"),
        ]),
        ("Layout", [
            ("Alt+b", "split horizontal"),
            ("Alt+v", "split vertical"),
            ("Alt+e", "toggle split"),
            ("Alt+w", "tabbed"),
            ("Alt+s", "stacking"),
            ("Alt+f", "fullscreen"),
        ]),
    ],
    [
        ("Focus and move", [
            ("Alt+hjkl", "focus"),
            ("Alt+arrows", "focus"),
            ("Alt+Shift+hjkl", "move window"),
            ("Alt+Space", "toggle focus mode"),
            ("Alt+Shift+Space", "float / tile"),
        ]),
        ("Resize", [
            ("Alt+r", "enter resize mode"),
            ("hjkl", "shrink or grow"),
            ("Enter", "leave resize mode"),
        ]),
    ],
    [
        ("Workspaces", [
            ("Alt+1 … 9", "switch workspace"),
            ("Alt+Shift+1 … 9", "send window there"),
        ]),
        ("Back to Windows", [
            ("Alt+Shift+z", "minimize, keys return"),
            ("Alt+Shift+e", "exit, asks first"),
            ("Exit", "top-right click"),
        ]),
    ],
]

DWM = [
    [
        ("Launch", [
            ("Alt+Shift+Enter", "open terminal"),
            ("Alt+p", "app launcher"),
            ("Alt+Shift+c", "close window"),
        ]),
        ("Layout", [
            ("Alt+t", "tiled"),
            ("Alt+m", "monocle"),
            ("Alt+f", "floating layout"),
            ("Alt+Space", "cycle layout"),
            ("Alt+Shift+Space", "float this window"),
            ("Alt+Return", "promote to master"),
        ]),
    ],
    [
        ("Focus and size", [
            ("Alt+j / k", "next / previous"),
            ("Alt+h / l", "shrink / grow master"),
            ("Alt+b", "toggle the bar"),
            ("Alt+i / d", "more / fewer masters"),
        ]),
    ],
    [
        ("Tags", [
            ("Alt+1 … 9", "view tag"),
            ("Alt+Shift+1 … 9", "send window there"),
        ]),
        ("Back to Windows", [
            ("Alt+Shift+z", "minimize, keys return"),
            ("Alt+Shift+q", "exit the session"),
            ("Exit", "top-right click"),
        ]),
    ],
]


def font(path, size):
    return ImageFont.truetype(path, size)


def text_size(draw, text, fnt):
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1], box[1]


def render(width, height, wm):
    columns = I3 if wm == "i3" else DWM
    scale = max(0.72, min(width / 1680, height / 980, 1.8))
    title_px = max(22, int(34 * scale))
    sub_px = max(13, int(16 * scale))
    head_px = max(14, int(18 * scale))
    key_px = max(13, int(16 * scale))
    body_px = max(13, int(16 * scale))

    im = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(im)
    title_f = font(FONT_SANS_BOLD, title_px)
    sub_f = font(FONT_SANS, sub_px)
    head_f = font(FONT_SANS_BOLD, head_px)
    key_f = font(FONT_MONO_BOLD, key_px)
    body_f = font(FONT_SANS, body_px)

    margin = int(56 * scale)
    title = "sucklesswsl"
    subtitle = "Alt is the modifier     ·     shown whenever a workspace is empty"
    tw, th, _ta = text_size(draw, title, title_f)
    _sw, sh, _sa = text_size(draw, subtitle, sub_f)
    gap = int(28 * scale)
    usable_w = width - 2 * margin
    col_w = (usable_w - gap * (len(columns) - 1)) // len(columns)
    row_gap = int(12 * scale)
    sec_gap = int(26 * scale)
    pad = int(18 * scale)

    def column_height(sections):
        total = 0
        for heading, rows in sections:
            _, hh, _ = text_size(draw, heading, head_f)
            total += hh + int(16 * scale)
            for keys, _what in rows:
                _, kh, _ = text_size(draw, keys, key_f)
                total += kh + int(8 * scale) + row_gap
            total += sec_gap
        return total

    card_h = max(column_height(sections) for sections in columns)
    header_h = th + sh + int(28 * scale)
    block_h = header_h + card_h + pad
    # Sit the sheet in the upper-middle, clear of the top-right session button.
    top = max(margin, (height - block_h) // 3)
    title_x = margin
    title_y = top
    draw.text((title_x, title_y), title, font=title_f, fill=TITLE)
    wm_label = wm
    _ww, wh, _wa = text_size(draw, wm_label, title_f)
    draw.text((title_x + tw + int(16 * scale), title_y + (th - wh) // 2), wm_label,
              font=title_f, fill=KEY_FG)
    draw.text((title_x, title_y + th + int(8 * scale)), subtitle, font=sub_f, fill=MUTED)

    cards_top = title_y + header_h
    for ci, sections in enumerate(columns):
        x = margin + ci * (col_w + gap)
        draw.rounded_rectangle(
            [x - pad, cards_top - pad, x + col_w + int(8 * scale), cards_top + card_h],
            radius=int(14 * scale), fill=CARD, outline=CARD_EDGE, width=1)
        y = cards_top
        for heading, rows in sections:
            draw.text((x, y), heading, font=head_f, fill=HEAD)
            _, hh, _ = text_size(draw, heading, head_f)
            y += hh + int(6 * scale)
            draw.line([(x, y), (x + col_w - int(12 * scale), y)], fill=RULE, width=1)
            y += int(10 * scale)
            for keys, what in rows:
                kw, kh, ka = text_size(draw, keys, key_f)
                pad_x = int(8 * scale)
                pad_y = int(4 * scale)
                cap_w = kw + 2 * pad_x
                cap_h = kh + 2 * pad_y
                draw.rounded_rectangle(
                    [x, y, x + cap_w, y + cap_h],
                    radius=int(4 * scale), fill=KEY_BG, outline=KEY_EDGE, width=1)
                draw.text((x + pad_x, y + pad_y - ka), keys, font=key_f, fill=KEY_FG)
                _, bh, ba = text_size(draw, what, body_f)
                draw.text((x + cap_w + int(12 * scale), y + (cap_h - bh) / 2 - ba),
                          what, font=body_f, fill=MUTED)
                y += cap_h + row_gap
            y += sec_gap

    return im


def set_root(image):
    """Copy image onto the X root window and keep it after this process exits."""
    x11 = ctypes.CDLL("libX11.so.6")
    c_void = ctypes.c_void_p
    c_ulong = ctypes.c_ulong
    c_uint = ctypes.c_uint
    c_int = ctypes.c_int

    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = c_void
    x11.XDefaultScreen.argtypes = [c_void]
    x11.XDefaultScreen.restype = c_int
    x11.XDefaultRootWindow.argtypes = [c_void]
    x11.XDefaultRootWindow.restype = c_ulong
    x11.XDefaultDepth.argtypes = [c_void, c_int]
    x11.XDefaultDepth.restype = c_int
    x11.XDefaultVisual.argtypes = [c_void, c_int]
    x11.XDefaultVisual.restype = c_void
    x11.XCreatePixmap.argtypes = [c_void, c_ulong, c_uint, c_uint, c_uint]
    x11.XCreatePixmap.restype = c_ulong
    x11.XCreateGC.argtypes = [c_void, c_ulong, c_ulong, c_void]
    x11.XCreateGC.restype = c_void
    x11.XCreateImage.argtypes = [c_void, c_void, c_uint, c_int, c_int,
                                 c_void, c_uint, c_uint, c_int, c_int]
    x11.XCreateImage.restype = c_void
    x11.XPutImage.argtypes = [c_void, c_ulong, c_void, c_void,
                              c_int, c_int, c_int, c_int, c_uint, c_uint]
    x11.XPutImage.restype = c_int
    x11.XSetWindowBackgroundPixmap.argtypes = [c_void, c_ulong, c_ulong]
    x11.XClearWindow.argtypes = [c_void, c_ulong]
    x11.XSetCloseDownMode.argtypes = [c_void, c_int]
    x11.XFlush.argtypes = [c_void]
    x11.XSync.argtypes = [c_void, c_int]
    x11.XImageByteOrder.argtypes = [c_void]
    x11.XImageByteOrder.restype = c_int

    class Visual(ctypes.Structure):
        _fields_ = [
            ("ext_data", c_void),
            ("visualid", c_ulong),
            ("c_class", c_int),
            ("red_mask", c_ulong),
            ("green_mask", c_ulong),
            ("blue_mask", c_ulong),
            ("bits_per_rgb", c_int),
            ("map_entries", c_int),
        ]

    dpy = x11.XOpenDisplay(None)
    if not dpy:
        sys.exit("wallpaper: cannot open DISPLAY")
    screen = x11.XDefaultScreen(dpy)
    root = x11.XDefaultRootWindow(dpy)
    depth = x11.XDefaultDepth(dpy, screen)
    visual = ctypes.cast(x11.XDefaultVisual(dpy, screen), ctypes.POINTER(Visual)).contents
    lsb = x11.XImageByteOrder(dpy) == 0

    width, height = image.size
    raw = image.convert("RGB").tobytes()
    rm, gm, bm = int(visual.red_mask), int(visual.green_mask), int(visual.blue_mask)

    def shift(mask):
        s = 0
        while mask and (mask & 1) == 0:
            mask >>= 1
            s += 1
        return s

    rs, gs, bs = shift(rm), shift(gm), shift(bm)
    bpp = 32 if depth >= 24 else 16
    nbytes = bpp // 8
    buf = ctypes.create_string_buffer(width * height * nbytes)
    o = 0
    for i in range(0, len(raw), 3):
        val = (((raw[i] << rs) & rm) | ((raw[i + 1] << gs) & gm) | ((raw[i + 2] << bs) & bm))
        for k in range(nbytes):
            buf[o + (k if lsb else nbytes - 1 - k)] = (val >> (8 * k)) & 0xFF
        o += nbytes

    pixmap = x11.XCreatePixmap(dpy, root, width, height, depth)
    gc = x11.XCreateGC(dpy, pixmap, 0, None)
    # bytes_per_line 0 tells Xlib the rows are packed tight.
    ximage = x11.XCreateImage(dpy, x11.XDefaultVisual(dpy, screen), depth,
                              2, 0, ctypes.cast(buf, c_void), width, height, 32, 0)
    if not ximage:
        sys.exit("wallpaper: XCreateImage failed")
    x11.XPutImage(dpy, pixmap, gc, ximage, 0, 0, 0, 0, width, height)
    x11.XSetWindowBackgroundPixmap(dpy, root, pixmap)
    x11.XClearWindow(dpy, root)
    # RetainPermanent: the pixmap stays after this process exits.
    x11.XSetCloseDownMode(dpy, 1)
    x11.XSync(dpy, 0)
    x11.XFlush(dpy)


def screen_size():
    x11 = ctypes.CDLL("libX11.so.6")
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XDefaultScreen.argtypes = [ctypes.c_void_p]
    x11.XDefaultScreen.restype = ctypes.c_int
    x11.XDisplayWidth.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x11.XDisplayWidth.restype = ctypes.c_int
    x11.XDisplayHeight.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x11.XDisplayHeight.restype = ctypes.c_int
    dpy = x11.XOpenDisplay(None)
    if not dpy:
        sys.exit("wallpaper: cannot open DISPLAY")
    screen = x11.XDefaultScreen(dpy)
    return x11.XDisplayWidth(dpy, screen), x11.XDisplayHeight(dpy, screen)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wm", choices=("i3", "dwm"), default="i3")
    ap.add_argument("--preview", help="write a PNG instead of setting the root")
    ap.add_argument("--size", default="1920x1080", help="used with --preview")
    args = ap.parse_args()
    if args.preview:
        w, h = (int(n) for n in args.size.lower().split("x"))
        render(w, h, args.wm).save(args.preview)
        return
    w, h = screen_size()
    set_root(render(w, h, args.wm))


if __name__ == "__main__":
    main()
