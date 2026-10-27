# Installing

This replaces whatever is on the phone's `userdata` partition, so everything on it
is lost. Read [`recovery.md`](recovery.md) before you start, and keep a known-good
`boot` image somewhere safe.

## What you need

* A Xiaomi Mi 5 (`gemini`) with an **unlocked bootloader**. Unlocking is not covered
  here: follow Xiaomi's official process or the
  postmarketOS wiki page for the Xiaomi Mi 5 (`xiaomi-gemini`).
  `fastboot getvar unlocked` must print `yes`.
* `fastboot` and `ssh` on the computer, a good USB **data** cable, and a battery
  above ~50 %.
* The two images, built as described in the [README](../README.md#build).
* Which screen you have. This build assumes the LG Display panel (`lgd`). A phone
  with the JDI panel needs `deviceinfo_dtb="qcom/msm8996-xiaomi-gemini"` in
  `pmaports/device/testing/device-xiaomi-gemini/deviceinfo` before building. A wrong
  panel gives a black screen, but USB networking still comes up.

## 1. Build the images

```sh
scripts/setup-build.sh
scripts/build.sh
scripts/make-images.sh
```

You get:

| File | What it is |
|---|---|
| `.build/images/boot.img` | the kernel, initramfs and cmdline to flash to `boot` |
| `.build/images/rootfs.img` | the root filesystem to flash to `userdata` |

To have the phone join your Wi-Fi at first boot, put a NetworkManager profile in
`.build/credentials/` before running `make-images.sh` (any `*.nmconnection`, mode
600). Otherwise you can add it later over USB with `nmcli`.

The build creates a login for the user `sacca`: the default password `sacca`
(change it by putting another one in `.build/credentials/user-password.txt` before
building, and with `passwd` afterwards) and an SSH key in `.build/ssh/`, which stays on
your machine.

## 2. Optional: boot without flashing

```sh
adb reboot bootloader        # or see recovery.md for other ways into fastboot
fastboot boot .build/images/boot.img
```

This loads the kernel from RAM and writes nothing. It only reaches a login if the
phone already holds the matching root filesystem, because the boot image names the
root partition by UUID and every build gets new UUIDs. So it is useful for testing
a new kernel on an installed phone, not for a fresh one. The screen keeps the stale
fastboot picture during a RAM boot; judge success over USB (step 4).

## 3. Flash

From fastboot:

```sh
fastboot flash boot     .build/images/boot.img
fastboot flash userdata .build/images/rootfs.img
fastboot reboot
```

Flash only these two partitions. Never touch `aboot`, `xbl`, `persist`, `modemst`,
`fsg` or the partition tables, and never relock the bootloader. The first boot grows
the root filesystem to fill `userdata`, so it takes longer than later ones.

## 4. First login

The phone appears as a USB network device and answers on `172.16.42.1`:

```sh
ssh-keygen -f ~/.ssh/known_hosts -R 172.16.42.1     # after every reflash
ssh sacca@172.16.42.1                                # password: sacca
# or with the generated key: ssh -i .build/ssh/gemini_ed25519 sacca@172.16.42.1
```

Run the on-device checks from your computer:

```sh
ssh -i .build/ssh/gemini_ed25519 sacca@172.16.42.1 'sh -s' < tests/kernel-smoke.sh
```

All 20 should pass. Known exception: on about 1 boot in 8 the Wi-Fi chip does not
appear on PCIe, which fails the Wi-Fi check. The phone reboots itself (`wifi-guard`,
at most twice) or you can reboot it by hand.

Joining Wi-Fi without a profile:

```sh
sudo nmcli device wifi connect "<ssid>" password "<password>"
```

## 5. Settings worth changing

* **Passwords:** the login `sacca` / `sacca` and SSH password login are on so a fresh
  phone is reachable, which is unsafe on any network you don't control. Run `passwd`
  right away. Once your key works, set
  `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/10-hardening.conf` and run
  `sudo rc-service sshd restart`. The overlay in `rootfs-overlay/` makes this the
  default for the next build if you edit it there.
* **Country and time zone:** Wi-Fi is set to regulatory domain `FR` in
  `rootfs-overlay/etc/modprobe.d/cfg80211-regdom.conf`, and the time zone is UTC.
  Change the domain to your country before building.
* **Battery:** `sudo battery-mode status`. For a phone that stays plugged in,
  `sudo battery-mode limit 70 80` keeps the battery between 70 and 80 %, and
  `sudo battery-mode bypass` runs from the cable and only charges below 20 %.
  `sudo battery-mode auto` goes back to normal charging.
* **Heat:** the big cores are capped at 1.55 GHz (`/etc/conf.d/cpucap`) and
  `thermal-guard` powers the phone off at 55 °C battery or 95 °C CPU. The log is
  `/var/lib/thermal-guard.log`.

## Updating later

Don't reflash. Follow "Updating a running phone" in [`kernel.md`](kernel.md); it keeps
your data and checks the boot image before writing it.
