# Charging test

**Not yet done.** The battery bypass was tested on a 500 mA computer USB port
(see [`docs/bringup-findings.md`](../docs/bringup-findings.md)). Charging from a wall
charger (DCP, up to 3 A) has not been tested. Don't mark anything as passed without
keeping the commands and output.

## Safety rules

- Be present and keep the phone visible. Do not run this unattended.
- Start with a **5 V charger limited to 1 A**. Go higher only after the temperature
  behaviour is known. A computer port can be misdetected as SDP and limited to 500 mA.
- Stop and unplug if the battery reaches **40 °C**, voltage goes above 4.4 V, the
  charge state looks inconsistent, or you see smoke, swelling or a smell. Hard limit 45 °C.
- Never write charger registers by hand, disable JEITA or charge termination, or
  bypass the under/over-voltage protections.
- Don't drain the battery below 20 % on purpose. Start the test between 30 and 70 %.
- Keep raw logs private (for example in `.build/`), never commit them.

## Procedure

Over SSH, with the phone at room temperature and out of any case:

1. **Baseline, unplugged from the charger:**
   ```sh
   for p in /sys/class/power_supply/*; do echo "== $p"; cat $p/uevent; done
   dmesg | grep -iE 'smbchg|qcom-fg|charger|battery'
   ```
   Make sure `battery-mode status` says `auto`.
2. **Detection:** plug in the 1 A charger and read the same `uevent` files. Check
   `USB_TYPE` (should be DCP), `INPUT_CURRENT_LIMIT` (not stuck at 500 mA), `STATUS`
   (Charging) and `CHARGE_TYPE`. Use the sysfs values, not the charger's label.
3. **Charge:** log capacity, voltage, current and temperature once a minute while the
   phone idles:
   ```sh
   while :; do date +%T; for f in capacity voltage_now current_now temp status; do
     printf '%s=%s ' $f "$(cat /sys/class/power_supply/qcom-battery/$f)"; done; echo
     sleep 60; done
   ```
   Watch the current taper and the move to `Full`. Voltage must stay at or below 4.4 V
   and charging must stop or drop at termination.
4. **Plug cycles:** unplug, wait 30 s, replug, three times. Check detection each time
   and `dmesg` for charger or fuel-gauge errors.
5. **Light load:** run something bounded, like repeated `sha256sum` of a file, for up
   to 10 minutes while charging. Watch the temperature.
6. Only then, if all of the above stayed cool, try a 2 A or 3 A charger.

## Known facts about this phone

- Charger `qcom-smbchg` and fuel gauge `qcom_fg` (PMI8994). The vendor kernel also
  uses an SMB1351 parallel charger, which this kernel does not support.
- The vendor kernel reports `ENABLE_JEITA_DETECTION=0`. Record what this kernel does
  with temperature (`HEALTH` in the battery `uevent`) instead of assuming.
- Battery profile `itech_3020mah`, designed for about 3 Ah.

## Passing

DCP detected and not limited to 500 mA, positive charge current, voltage at or below
4.4 V, reaches `Full` and terminates, three clean plug cycles, and temperature stays
below 40 °C. Any failure must be reproduced and traced to a driver or device-tree
cause before changing a patch.
