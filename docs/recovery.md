# Recovery

Rules: never relock the bootloader, never touch `aboot`, `xbl`, `persist`, `modemst`,
`fsg` or the GPTs, and keep the phone above ~50 % battery during any flash.

## Before you flash

1. Boot unlocked: `fastboot getvar unlocked` should say `yes`.
2. Keep a known-good `boot` image (your original, or a previous working build of
   this repository). Hash it and store it outside the repo.
3. Remember that flashing `userdata` destroys everything on it.
4. Try first without flashing: `fastboot boot <boot image>`. This works on the
   tested unit. The panel keeps showing the stale fastboot picture during a RAM
   boot, so check over USB networking over SSH.

## Getting into fastboot

* From Linux on the phone, as root, after `sync`:
  ```sh
  python3 -c 'import ctypes; ctypes.CDLL(None).syscall(142,0xfee1dead,672274793,0xA1B2C3D4,b"bootloader")'
  ```
* From Android: `adb reboot bootloader`.
* Otherwise: power off, then hold Volume Down while plugging in USB (standard
  Xiaomi entry; not verified here).

## Rollback

* **Bad kernel, rootfs still fine:** `fastboot flash boot <known-good boot image>`.
* **From a working system:** `sudo gemini-boot-update --restore /var/lib/boot-backup/boot-<stamp>.img --yes`.
* **Back to Android/LineageOS:** flash the original `boot` and `recovery` images you
  saved, then reinstall the ROM from recovery. `userdata` cannot be restored
  without a backup of it.

## If a flash fails

1. Unplug USB if the phone is abnormally hot.
2. Do not retry the same command repeatedly; record the exact fastboot error.
3. Re-enter fastboot, check `fastboot devices`, and flash a known-good boot image
   rather than another experimental one.
4. If the phone does not enumerate, stop. Do not attempt blind partition writes.

## Debugging a hang

The bootloader reserves a ramoops region, so a hung kernel's log survives a
reset. Reboot to fastboot, boot any pstore-enabled kernel, and read
`/sys/fs/pstore/console-ramoops-0`. A long power-button hold wipes it.
