#!/usr/bin/env python3
"""
Find the device path and key code for your star/favourite key.

Run this, press the key, and it will print the config values
to paste into mediacontrols.py.

You need to be in the 'input' group (or run as root):
    sudo usermod -aG input $USER   # then log out and back in
"""

import sys
import selectors

try:
    import evdev
    from evdev import InputDevice, categorize, ecodes
except ImportError:
    print("Install python-evdev:  pip install evdev")
    sys.exit(1)


def main():
    # List all devices
    paths = evdev.list_devices()
    devices = []
    for path in paths:
        try:
            devices.append(InputDevice(path))
        except PermissionError:
            print(f"  [no permission] {path}")
        except Exception:
            pass

    if not devices:
        print("No accessible input devices found.")
        print("Try:  sudo usermod -aG input $USER  then log out/in")
        sys.exit(1)

    print("Accessible input devices:")
    print("-" * 60)
    for dev in devices:
        print(f"  {dev.path:20s}  {dev.name}")
    print()
    print("Press your STAR key (Ctrl+C to quit)...")
    print()

    sel = selectors.DefaultSelector()
    for dev in devices:
        sel.register(dev, selectors.EVENT_READ)

    seen = set()
    try:
        while True:
            ready = sel.select(timeout=0.1)
            for key, _ in ready:
                dev = key.fileobj
                try:
                    for event in dev.read():
                        if event.type == ecodes.EV_KEY and event.value == 1:
                            kev = categorize(event)
                            sig = (dev.path, kev.keycode)
                            if sig in seen:
                                continue
                            seen.add(sig)

                            print(f"┌─ KEY DETECTED ─────────────────────────────┐")
                            print(f"│  Device path : {dev.path}")
                            print(f"│  Device name : {dev.name}")
                            print(f"│  Key code    : {kev.keycode}")
                            print(f"└────────────────────────────────────────────┘")
                            print()
                            print("Paste these into the CONFIG dict in mediacontrols.py:")
                            print(f"    'star_device':  '{dev.path}',")
                            print(f"    'star_keycode': '{kev.keycode}',")
                            print()
                            print("Also run this to find your keyboard device (for arrow-key grab):")
                            print("    Press any letter key...")
                            print()
                except Exception:
                    pass
    except KeyboardInterrupt:
        print("\nDone.")
    finally:
        for dev in devices:
            try:
                dev.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()
