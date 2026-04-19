#!/usr/bin/env python3
import os
import threading
from evdev import AbsInfo, InputDevice, UInput, ecodes

MFD_JOYSTICK_VERSION = "1.0.0"

# Configuration for MFD 1 and MFD 2
DEVICES = [
{
"path": "/dev/input/by-id/usb-Thrustmaster_F16_MFD_1-event-joystick",
"name": "Thrustmaster F16 MFD 1 (Virtual)",
"vendor": 0x044F,
"product": 0xFF01,
"mapping": [319, 704, 705, 706, 707, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 708, 709, 710, 711, 712, 713, 714, 715]
},
{
"path": "/dev/input/by-id/usb-Thrustmaster_F16_MFD_2-event-joystick",
"name": "Thrustmaster F16 MFD 2 (Virtual)",
"vendor": 0x044F,
"product": 0xFF02,
"mapping": [319, 704, 705, 706, 707, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 708, 709, 710, 711, 712, 713, 714, 715]
}
]

# Keep button codes out of BTN_GAMEPAD range (0x130-0x13f) so Linux input
# stacks classify this as joystick-style rather than gamepad-style.
JOYSTICK_BUTTONS = [
	ecodes.BTN_TRIGGER,
	ecodes.BTN_THUMB,
	ecodes.BTN_THUMB2,
	ecodes.BTN_TOP,
	ecodes.BTN_TOP2,
	ecodes.BTN_PINKIE,
	ecodes.BTN_BASE,
	ecodes.BTN_BASE2,
	ecodes.BTN_BASE3,
	ecodes.BTN_BASE4,
	ecodes.BTN_BASE5,
	ecodes.BTN_BASE6,
	ecodes.BTN_DEAD,
]

# Extend to 28 logical buttons with non-gamepad key codes.
TARGET_BUTTONS = JOYSTICK_BUTTONS + [
	getattr(ecodes, f"BTN_TRIGGER_HAPPY{i}") for i in range(1, 16)
]

# Advertise only a minimal absolute-axis pair so the virtual device still
# looks like a joystick without carrying unused axes or POV hats.
AXIS_CAPS = [
	(ecodes.ABS_X, AbsInfo(value=0, min=0, max=65535, fuzz=0, flat=0, resolution=0)),
	(ecodes.ABS_Y, AbsInfo(value=0, min=0, max=65535, fuzz=0, flat=0, resolution=0)),
]


def should_grab_physical_devices():
	value = os.environ.get("BMS_MFD_GRAB_PHYSICAL", "1").strip().lower()
	return value not in {"0", "false", "no", "off"}

def handle_device(config):
	ui = None
	dev = None
	grabbed = False
	try:
		dev = InputDevice(config["path"])
		ui = UInput(
			{ecodes.EV_KEY: TARGET_BUTTONS, ecodes.EV_ABS: AXIS_CAPS},
			name=config["name"],
			bustype=0x03,
			vendor=config["vendor"],
			product=config["product"],
			version=0x0001,
		)
		if should_grab_physical_devices():
			try:
				dev.grab()
				grabbed = True
			except OSError as error:
				print(f"Warning: could not exclusively grab {config['name']} ({error}). Physical device may still be visible.")
		mapping_dict = dict(zip(config["mapping"], TARGET_BUTTONS))
		print(f"Enabled: {config['name']}")
		for event in dev.read_loop():
			if event.type == ecodes.EV_KEY and event.code in mapping_dict:
				ui.write(ecodes.EV_KEY, mapping_dict[event.code], event.value)
				ui.syn()
	except Exception as e:
		print(f"Info: {config['name']} not ready ({e})")
	finally:
		if grabbed and dev is not None:
			try:
				dev.ungrab()
			except OSError:
				pass
		if ui is not None:
			ui.close()

if __name__ == "__main__":
	if should_grab_physical_devices():
		print(f"MFD combo helper v{MFD_JOYSTICK_VERSION} active with exclusive grab enabled. Press Ctrl+C to exit.")
	else:
		print(f"MFD combo helper v{MFD_JOYSTICK_VERSION} active without grabbing physical devices. Press Ctrl+C to exit.")
	threads = [threading.Thread(target=handle_device, args=(d,), daemon=True) for d in DEVICES]
	for t in threads: t.start()
	try:
		for t in threads: t.join()
	except KeyboardInterrupt:
		print("\nExited.")
