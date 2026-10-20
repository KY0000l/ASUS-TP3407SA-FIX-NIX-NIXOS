import glob
import time

from evdev import UInput, ecodes as e

# Measured on the TP3407SA: ~103 normal, ~177 flat, 336 tent, 360 tablet.
ENTER = 300  # degrees: at or above this -> tablet mode
EXIT = 270   # degrees: at or below this -> back to laptop mode
POLL = 0.25  # seconds


def find_hinge():
    for dev in sorted(glob.glob("/sys/bus/iio/devices/iio:device*")):
        try:
            if open(dev + "/name").read().strip() != "hinge":
                continue
            for label in sorted(glob.glob(dev + "/in_angl*_label")):
                if open(label).read().strip() == "hinge":
                    return label.replace("_label", "_raw")
        except OSError:
            pass
    return None


def read_angle(path):
    try:
        return int(open(path).read().strip())
    except (OSError, ValueError):
        return None


path = None
while path is None:
    path = find_hinge()
    if path is None:
        time.sleep(2)

ui = UInput({e.EV_SW: [e.SW_TABLET_MODE]}, name="Hinge Tablet Mode Switch")

tablet = None
while True:
    angle = read_angle(path)
    if angle is not None:
        new = tablet
        if tablet is None:
            new = angle >= ENTER
        elif not tablet and angle >= ENTER:
            new = True
        elif tablet and angle <= EXIT:
            new = False
        if new != tablet:
            tablet = new
            ui.write(e.EV_SW, e.SW_TABLET_MODE, 1 if tablet else 0)
            ui.syn()
    time.sleep(POLL)
