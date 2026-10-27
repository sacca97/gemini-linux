#!/usr/bin/env python3
"""Wake the console on any hardware button, toggle it with the power button, and keep the blank timeout.

The kernel console does not unblank on gpio-keys / pmic key events on this
phone, so listen on the power, volume and home keys and send
TIOCL_UNBLANKSCREEN to the virtual console ourselves. The power key blanks the
screen when it is on.
"""
import fcntl
import os
import re
import select
import struct

EVENT = struct.Struct("llHHi")  # struct input_event on 64-bit
EV_KEY = 1
TIOCLINUX = 0x541C
TIOCL_UNBLANKSCREEN = 4
TIOCL_BLANKSCREEN = 14
FB_BLANK = "/sys/class/graphics/fb0/blank"
POWER_KEY = "pm8941_pwrkey"
BLANK_PARAM = "/sys/module/kernel/parameters/consoleblank"
BLANK_SECONDS = 60
CHECK_MS = 10000
WANTED = ("pm8941_pwrkey", "pm8941_resin", "gpio-keys")


def event_nodes():
    nodes = []
    for block in open("/proc/bus/input/devices").read().split("\n\n"):
        name = re.search(r'^N: Name="(.*)"$', block, re.M)
        handlers = re.search(r"^H: Handlers=(.*)$", block, re.M)
        if name and handlers and name.group(1) in WANTED:
            nodes += [("/dev/input/" + h, name.group(1)) for h in handlers.group(1).split() if h.startswith("event")]
    return nodes


def console_ioctl(subcode):
    fd = os.open("/dev/tty0", os.O_RDWR | os.O_NOCTTY)
    try:
        fcntl.ioctl(fd, TIOCLINUX, bytes([subcode]))
    finally:
        os.close(fd)


def screen_blanked():
    try:
        return int(open(FB_BLANK).read()) != 0
    except (OSError, ValueError):
        return False


def keep_blank_timeout():
    """Something at boot resets the timeout to 300 s; put it back whenever it drifts."""
    try:
        if int(open(BLANK_PARAM).read()) == BLANK_SECONDS:
            return
        # ESC [ 9 ; n ] sets the blank timeout in minutes
        with open("/dev/tty0", "w") as tty:
            tty.write("\033[9;%d]" % (BLANK_SECONDS // 60))
    except (OSError, ValueError):
        pass


def main():
    fds = {os.open(n, os.O_RDONLY): name for n, name in event_nodes()}
    if not fds:
        raise SystemExit("no key input devices found")
    poll = select.poll()
    for fd in fds:
        poll.register(fd, select.POLLIN)
    while True:
        keep_blank_timeout()
        for fd, _ in poll.poll(CHECK_MS):
            data = os.read(fd, EVENT.size * 16)
            for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, etype, _, value = EVENT.unpack_from(data, off)
                if etype == EV_KEY and value == 1:
                    if fds[fd] == POWER_KEY and not screen_blanked():
                        console_ioctl(TIOCL_BLANKSCREEN)
                    else:
                        console_ioctl(TIOCL_UNBLANKSCREEN)


if __name__ == "__main__":
    main()
