#!/usr/bin/env python3
"""
sucklesswsl — floating exit button.

A small always-on-top button inside the WM session (override-redirect, so it
floats above i3 and dwm without per-WM rules). One click ends the session.
There is no confirm step: a second question is just another click that can
miss. Alt+Shift+z still minimizes without quitting.
"""
import argparse
import os
import signal
import sys

try:
    import tkinter as tk
except Exception as exc:  # pragma: no cover - handled by caller
    sys.stderr.write(f"session-control: tkinter unavailable: {exc}\n")
    sys.exit(2)

BG = "#1f2430"
BG_HOVER = "#e05252"
FG = "#e6e6e6"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--session-pid", type=int, default=0,
                    help="PID of startwm.sh; SIGTERM ends the session")
    ap.add_argument("--label", default="⏻  Exit",
                    help="text shown on the button")
    args = ap.parse_args()

    root = tk.Tk()
    root.title("sucklesswsl-control")
    root.overrideredirect(True)
    root.attributes("-topmost", True)

    def end_session(_e=None):
        if args.session_pid > 0:
            try:
                os.kill(args.session_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        root.destroy()
        os._exit(0)

    pill = tk.Label(root, text=args.label, bg=BG, fg=FG,
                    font=("monospace", 11), padx=14, pady=8, cursor="hand2")
    pill.pack()
    pill.bind("<Button-1>", end_session)
    pill.bind("<Enter>", lambda _e: pill.config(bg=BG_HOVER, fg="#ffffff"))
    pill.bind("<Leave>", lambda _e: pill.config(bg=BG, fg=FG))

    def place():
        root.update_idletasks()
        w = root.winfo_reqwidth()
        h = root.winfo_reqheight()
        sw = root.winfo_screenwidth()
        root.geometry(f"{w}x{h}+{max(0, sw - w - 12)}+12")

    def keep_on_top():
        try:
            root.attributes("-topmost", True)
            root.lift()
        except tk.TclError:
            return
        root.after(1500, keep_on_top)

    place()
    keep_on_top()
    root.mainloop()


if __name__ == "__main__":
    main()
