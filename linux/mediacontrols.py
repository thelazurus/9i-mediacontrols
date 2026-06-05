#!/usr/bin/env python3
"""
9i Media Controls — Linux (KDE / Wayland)

Press the star key to enter MEDIA MODE, then:
    ←  Previous track      →  Next track
    ↑  Volume up           ↓  Volume down
    Space  Play / Pause    Esc  Exit mode

Requirements:
    pip install evdev PyQt6
    sudo usermod -aG input $USER   (then log out/in)
    playerctl, wpctl (PipeWire) or pactl (PulseAudio)

Run find_keys.py first to fill in the CONFIG values below.
"""

import sys
import os
import threading
import subprocess
import time

# ── CONFIG ──────────────────────────────────────────────────────
#  Run find_keys.py to determine these values for your machine.
CONFIG = {
    # Device that sends the star / favourite key
    "star_device":      "/dev/input/event0",    # <─── update
    "star_keycode":     "KEY_FAVORITES",         # <─── update

    # Main keyboard (for arrow-key intercept while in mode)
    # Run find_keys.py and press a letter key to find this.
    "keyboard_device":  "/dev/input/event3",    # <─── update

    "timeout_ms":  2500,    # ms of inactivity before mode exits
    "vol_step":    5,        # volume percent per arrow press
}
# ────────────────────────────────────────────────────────────────

try:
    import evdev
    from evdev import InputDevice, categorize, ecodes, UInput
except ImportError:
    print("Missing dependency:  pip install evdev")
    sys.exit(1)

try:
    from PyQt6.QtWidgets import QApplication, QWidget
    from PyQt6.QtCore import Qt, QTimer, QObject, pyqtSignal
    from PyQt6.QtGui import QPainter, QColor, QFont, QPen
except ImportError:
    print("Missing dependency:  pip install PyQt6")
    sys.exit(1)


# ════════════════════════════════════════════════════════════════
#  OSD WINDOW
# ════════════════════════════════════════════════════════════════

class OSDWindow(QWidget):
    """Retro amber-phosphor on-screen display."""

    AMBER     = QColor(0xFF, 0xB0, 0x00)
    AMBER_DIM = QColor(0x7A, 0x52, 0x00)
    AMBER_BDR = QColor(0xA0, 0x6A, 0x00)
    BG        = QColor(0x0C, 0x0C, 0x0C, 238)

    W, H = 440, 115

    def __init__(self):
        super().__init__()
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.Tool |
            Qt.WindowType.WindowDoesNotAcceptFocus |
            Qt.WindowType.BypassWindowManagerHint,
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WidgetAttribute.WA_X11DoNotAcceptFocus)

        screen = QApplication.primaryScreen().availableGeometry()
        self._x = screen.x() + (screen.width() - self.W) // 2
        self._y_shown  = screen.y() + screen.height() - self.H - 50
        self._y_hidden = self._y_shown + 28

        self.setGeometry(self._x, self._y_hidden, self.W, self.H)

        self._opacity     = 0.0
        self._cur_y       = float(self._y_hidden)
        self._action_text = ""
        self._hints_text  = ""
        self._anim_dir    = 0   # 1=in  -1=out  0=idle

        self._anim_timer = QTimer(self)
        self._anim_timer.setInterval(16)
        self._anim_timer.timeout.connect(self._tick)

        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self._begin_fade_out)

    # ── public API (call from main thread via signal) ────────────

    def show_action(self, action: str, hints: str):
        self._action_text = action
        self._hints_text  = hints
        self._hide_timer.stop()
        self._anim_dir = 1
        if not self.isVisible():
            self._opacity = 0.0
            self._cur_y   = float(self._y_hidden)
            self.move(self._x, self._y_hidden)
            self.show()
        self._anim_timer.start()
        self._hide_timer.start(CONFIG["timeout_ms"])
        self.update()

    def force_hide(self):
        self._hide_timer.stop()
        self._begin_fade_out()

    # ── animation ───────────────────────────────────────────────

    def _begin_fade_out(self):
        self._anim_dir = -1
        self._anim_timer.start()

    def _tick(self):
        if self._anim_dir == 1:
            self._opacity = min(1.0, self._opacity + 0.14)
            self._cur_y  += (self._y_shown - self._cur_y) * 0.35
            if self._opacity >= 1.0:
                self._opacity = 1.0
                self._cur_y   = float(self._y_shown)
                self._anim_dir = 0
                self._anim_timer.stop()
        elif self._anim_dir == -1:
            self._opacity = max(0.0, self._opacity - 0.14)
            if self._opacity <= 0.0:
                self._opacity  = 0.0
                self._anim_dir = 0
                self._anim_timer.stop()
                self.hide()
                return

        self.move(self._x, round(self._cur_y))
        self.setWindowOpacity(self._opacity)
        self.update()

    # ── painting ────────────────────────────────────────────────

    def paintEvent(self, _event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, False)

        # Background
        p.fillRect(self.rect(), self.BG)

        # Scanlines
        scanline = QColor(0, 0, 0, 55)
        for y in range(0, self.H, 2):
            p.fillRect(0, y, self.W, 1, scanline)

        # Outer border
        pen = QPen(self.AMBER_BDR, 1.5)
        p.setPen(pen)
        p.drawRect(1, 1, self.W - 3, self.H - 3)

        # Divider above hint bar
        p.setPen(QPen(self.AMBER_DIM, 1))
        p.drawLine(12, self.H - 34, self.W - 12, self.H - 34)

        # Action label
        p.setPen(self.AMBER)
        font = QFont("Courier New", 20, QFont.Weight.Bold)
        font.setStyleHint(QFont.StyleHint.Monospace)
        p.setFont(font)
        p.drawText(0, 10, self.W, self.H - 44,
                   Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignVCenter,
                   self._action_text)

        # Hint bar
        p.setPen(self.AMBER_DIM)
        font2 = QFont("Courier New", 9)
        font2.setStyleHint(QFont.StyleHint.Monospace)
        p.setFont(font2)
        p.drawText(0, self.H - 30, self.W, 26,
                   Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignVCenter,
                   self._hints_text)

        p.end()


# ════════════════════════════════════════════════════════════════
#  SIGNALS  (thread → Qt main thread)
# ════════════════════════════════════════════════════════════════

class Signals(QObject):
    show_action = pyqtSignal(str, str)
    force_hide  = pyqtSignal()


# ════════════════════════════════════════════════════════════════
#  MEDIA HELPERS
# ════════════════════════════════════════════════════════════════

def _run(cmd: list[str]) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        return r.stdout.strip()
    except Exception:
        return ""

def _get_volume() -> int:
    """Return current default sink volume as 0-100 int."""
    out = _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    # "Volume: 0.75" or "Volume: 0.75 [MUTED]"
    try:
        return min(100, round(float(out.split()[1]) * 100))
    except Exception:
        pass
    # pactl fallback
    out = _run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
    try:
        return int(out.split("%")[0].split()[-1])
    except Exception:
        return 50

def _vol_up(step: int):
    if _run(["which", "wpctl"]):
        _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{step}%+"])
    else:
        _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"+{step}%"])

def _vol_down(step: int):
    if _run(["which", "wpctl"]):
        _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{step}%-"])
    else:
        _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"-{step}%"])

def _make_bar(vol: int) -> str:
    filled = round(vol / 10)
    bar = "█" * filled + "░" * (10 - filled)
    return f"[{bar}]  {vol}%"

HINTS = "←  prev    →  next    ↑  vol+    ↓  vol−    Space  play    Esc  exit"


# ════════════════════════════════════════════════════════════════
#  INPUT CONTROLLER  (runs in background threads)
# ════════════════════════════════════════════════════════════════

class InputController:
    def __init__(self, signals: Signals):
        self._sig   = signals
        self._mode  = False
        self._kbd   = None
        self._ui    = None
        self._lock  = threading.Lock()

    def start(self):
        t = threading.Thread(target=self._star_loop, daemon=True, name="star-reader")
        t.start()

    # ── star key loop ────────────────────────────────────────────

    def _star_loop(self):
        try:
            dev = InputDevice(CONFIG["star_device"])
            dev.grab()
        except FileNotFoundError:
            print(f"ERROR: star device not found: {CONFIG['star_device']}")
            print("       Run find_keys.py to get the correct path.")
            return
        except PermissionError:
            print("ERROR: cannot grab input device — not in 'input' group?")
            print("       sudo usermod -aG input $USER   (then log out/in)")
            return

        print(f"Listening on {dev.path} ({dev.name})")

        for event in dev.read_loop():
            if event.type == ecodes.EV_KEY and event.value == 1:
                kev = categorize(event)
                if kev.keycode == CONFIG["star_keycode"]:
                    if not self._mode:
                        self._enter_mode()
                    else:
                        self._exit_mode()

    # ── mode management ──────────────────────────────────────────

    def _enter_mode(self):
        self._mode = True
        self._sig.show_action.emit("◆  MEDIA MODE", HINTS)

        try:
            kbd = InputDevice(CONFIG["keyboard_device"])
            # Create passthrough virtual device before grabbing
            ui = UInput.from_device(kbd, name="9i-mediacontrols-passthrough")
            time.sleep(0.05)   # give udev a moment to register the new device
            kbd.grab()
            with self._lock:
                self._kbd = kbd
                self._ui  = ui
        except Exception as e:
            print(f"WARNING: cannot grab keyboard ({e}) — arrow keys won't be intercepted")
            # Mode still works for showing the OSD, just won't eat arrow key events
            return

        # Read keyboard in this thread until mode exits
        try:
            for event in kbd.read_loop():
                if not self._mode:
                    break
                self._handle_kbd_event(event)
        except Exception:
            pass
        finally:
            self._release_kbd()

    def _exit_mode(self):
        self._mode = False
        self._sig.force_hide.emit()
        self._release_kbd()

    def _release_kbd(self):
        with self._lock:
            if self._ui:
                try:
                    self._ui.close()
                except Exception:
                    pass
                self._ui = None
            if self._kbd:
                try:
                    self._kbd.ungrab()
                except Exception:
                    pass
                self._kbd = None

    # ── keyboard event routing ───────────────────────────────────

    def _handle_kbd_event(self, event):
        if event.type == ecodes.EV_KEY and event.value == 1:   # keydown only for media
            kev = categorize(event)
            if kev.keycode == "KEY_LEFT":
                self._do_media("PREV"); return
            if kev.keycode == "KEY_RIGHT":
                self._do_media("NEXT"); return
            if kev.keycode == "KEY_UP":
                self._do_media("VOLUP"); return
            if kev.keycode == "KEY_DOWN":
                self._do_media("VOLDOWN"); return
            if kev.keycode in ("KEY_SPACE", "KEY_ENTER"):
                self._do_media("PLAY"); return
            if kev.keycode == "KEY_ESC":
                self._exit_mode(); return

        # Pass everything else through unchanged
        with self._lock:
            if self._ui:
                try:
                    self._ui.write(event.type, event.code, event.value)
                    if event.type == ecodes.EV_SYN:
                        pass  # write already syncs for SYN events
                    else:
                        self._ui.syn()
                except Exception:
                    pass

    # ── media actions ────────────────────────────────────────────

    def _do_media(self, action: str):
        step = CONFIG["vol_step"]
        if action == "PREV":
            _run(["playerctl", "previous"])
            self._sig.show_action.emit("◄◄  PREV TRACK", HINTS)
        elif action == "NEXT":
            _run(["playerctl", "next"])
            self._sig.show_action.emit("NEXT TRACK  ►►", HINTS)
        elif action == "VOLUP":
            _vol_up(step)
            self._sig.show_action.emit(f"VOL  {_make_bar(_get_volume())}", HINTS)
        elif action == "VOLDOWN":
            _vol_down(step)
            self._sig.show_action.emit(f"VOL  {_make_bar(_get_volume())}", HINTS)
        elif action == "PLAY":
            _run(["playerctl", "play-pause"])
            self._sig.show_action.emit("▌▌  PLAY / PAUSE", HINTS)


# ════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════

def main():
    # KDE Wayland: tell Qt to use the native Wayland backend.
    # If the OSD doesn't appear on top, try:
    #   QT_QPA_PLATFORM=xcb python mediacontrols.py
    os.environ.setdefault("QT_QPA_PLATFORM", "wayland")

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    sig = Signals()
    osd = OSDWindow()

    sig.show_action.connect(osd.show_action)
    sig.force_hide.connect(osd.force_hide)

    ctrl = InputController(sig)
    ctrl.start()

    print("9i Media Controls running — press the star key to enter media mode.")
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
