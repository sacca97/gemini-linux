# Linux on the Xiaomi Mi 5 (gemini)

A headless Linux server on a Xiaomi Mi 5 (MSM8996 / Snapdragon 820), built on
[postmarketOS](https://postmarketos.org) v26.06 (now renamed Nura) with a lightly
patched `6.19.5` kernel. Boots to SSH over USB and Wi-Fi, idles in deep CPU sleep,
and can run from the cable alone with the battery bypassed.

> **Status:** running on a real phone, soak testing not done. It works on one unit
> (LG Display panel). Flashing is destructive and can brick the device: read
> [`docs/recovery.md`](docs/recovery.md) first. Use at your own risk.

## What works

| | |
|---|---|
| SSH | USB gadget network (172.16.42.1) and Wi-Fi (QCA6174) |
| Power | PSCI deep idle, cpufreq, big cluster capped at 1.55 GHz to limit heat |
| Sensors | 15 thermal zones, fuel gauge, hardware watchdog |
| Battery | `battery-mode auto \| bypass \| limit LOW HIGH` (kernel `charge_behaviour`) |
| Safety | `thermal-guard` powers off at 55 °C battery / 95 °C CPU |
| Screen | Power button blanks/wakes the console; auto blank after 60 s |

Known problems: the Wi-Fi chip fails to enumerate on PCIe on about 1 boot in 8
(`wifi-guard` reboots around it); GPU rendering, USB host mode and wall-charger
(3 A) charging are untested; the Mi 5 variant with the JDI panel needs a one-line
change (see [`docs/kernel.md`](docs/kernel.md)).

## Repository layout

| Path | Contents |
|---|---|
| `patches/kernel/` | 9 kernel patches on top of `v6.19.5-msm8996` |
| `pmaports/` | Kernel and device package definitions (`-r100`) |
| `rootfs-overlay/` | Services and settings applied to the image |
| `scripts/` | Build, boot-test, and update tooling |
| `tests/` | On-device smoke test, charging test plan |
| `docs/` | [Install](docs/install.md), [kernel](docs/kernel.md), [bring-up findings](docs/bringup-findings.md), [recovery](docs/recovery.md) |

## Build

Needs Docker and a few tens of GB of disk (tested on Fedora 44). Nothing
below touches a phone.

```sh
scripts/setup-build.sh          # pinned pmbootstrap container + pmaports v26.06
scripts/build.sh                # kernel, packages, rootfs, boot image -> .build/export/
scripts/check-kernel-config.sh  # static checks
scripts/make-images.sh          # apply rootfs-overlay -> .build/images/{boot,rootfs}.img
```

Try a kernel without flashing: `fastboot boot .build/images/boot.img`, then run
`ssh <phone> 'sh -s' < tests/kernel-smoke.sh`.

Generated credentials (SSH key, user password, Wi-Fi profile) live in
`.build/credentials/`, which is gitignored. You must supply your own Wi-Fi profile.

## Install

Unlocked bootloader required. Back up anything you care about: flashing `userdata`
erases it. Never touch `aboot`, `xbl`, `persist`, `modemst`, `fsg` or the GPTs, and
never relock the bootloader.

```sh
fastboot flash boot     <boot image>
fastboot flash userdata <rootfs image>
```

Step-by-step guide: [`docs/install.md`](docs/install.md). To update the kernel on an installed phone, see [`docs/kernel.md`](docs/kernel.md).

## License

Scripts, the rootfs overlay and the docs are MIT ([`LICENSE`](LICENSE)). The kernel
patches in `patches/kernel/` are GPL-2.0, like the kernel they modify. The files in
`pmaports/` derive from postmarketOS package definitions and keep their upstream
licenses.

## Credits

Kernel fork and postmarketOS packaging by Yassine Oudjana and the postmarketOS
community; this repository adds the patches and tooling listed above.
