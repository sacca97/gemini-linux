# Kernel distribution

How the gemini kernel is built, packaged, verified, updated and rolled back.
Everything is reproducible from this repository plus the pinned pmaports checkout
(`scripts/setup-build.sh`). Nothing below touches the phone unless a step says so.

## What is shipped

| Package | Source of truth | Notes |
|---|---|---|
| `linux-postmarketos-qcom-msm8996` 6.19.5-r100 | `pmaports/device/testing/linux-postmarketos-qcom-msm8996/` (APKBUILD, config) + `patches/kernel/` | Upstream pmOS kernel tag `v6.19.5-msm8996` plus our series |
| `device-xiaomi-gemini` 3-r100 | `pmaports/device/testing/device-xiaomi-gemini/` | Selects the LG Display board file (`deviceinfo_dtb`) and loads the panel module in the initramfs |

`pkgrel` is 100 so that our packages always sort above the stock `-r0` of the same
version. When the kernel tag moves (6.19.6 and later), keep `pkgrel=100` and rebase the
series; bump `pkgrel` for every rebuild that changes the output.

Boot image, initramfs and modules are produced by the normal pmOS tooling from these two
packages. The earlier hand-patched initramfs (dwc3 re-bind, firmware timeout) and the
hand-built cmdline are no longer needed: the USB PHY clock fix is in the kernel
(patch 0005) and the firmware fallback is disabled in the config.

## Patch series (`patches/kernel/`)

All patches are `git format-patch` output against `v6.19.5-msm8996`, with a commit
message and `Signed-off-by`. Review authorship and the copyright line in the panel
driver before sending anything upstream.

| # | Subject | Scope | Upstream readiness |
|---|---|---|---|
| 0001 | power: supply: qcom_fg: initialise SRAM state before registering the supply | Fixes a WARN on every boot | Ready; small bug fix |
| 0002 | backlight: qcom-wled: do not enable the OVP IRQ twice | Bug fix | Ready |
| 0003 | arm64: dts: msm8996: add the APSS watchdog | SoC-wide | Check the timeout and clock against other qcom boards first |
| 0004 | arm64: dts: msm8996: mark the CPU power collapse state local-timer-stop | SoC-wide; fixes a boot hang with PSCI cpuidle | Ready; tested on one unit only |
| 0005 | arm64: dts: msm8996-xiaomi-gemini: enable the USB PHY reference clock early | Board | Needs a review of the "iface" clock trick; may belong in the SoC file |
| 0006 | arm64: dts: msm8996-xiaomi-gemini: describe the two wired WLED strings | Board | Ready |
| 0007 | drm/panel: add LG Display TD4322 command-mode panel driver | New driver | Needs a DT binding document and a real copyright review |
| 0008 | arm64: dts: qcom: add msm8996-xiaomi-gemini-lgd for LG Display panel units | Board variant | Depends on 0007 |
| 0009 | power: supply: qcom-smbchg: add charge_behaviour inhibit-charge | Feature | Ready |

Dropped: the PCIe link-retry patch. It was safe but never recovered a natural link
failure (see `docs/bringup-findings.md`).

Kernel config delta against stock pmOS: `CONFIG_QCOM_TSENS=y`,
`CONFIG_ARM_PSCI_CPUIDLE=y`, `CONFIG_CPU_IDLE_GOV_TEO=y`,
`CONFIG_DRM_PANEL_LGD_TD4322=m`, `# CONFIG_FW_LOADER_USER_HELPER_FALLBACK is not set`.

## Building

```
scripts/build.sh            # sync-pmaports + kernel + rootfs + boot image
scripts/check-kernel-config.sh
```

`scripts/sync-pmaports.sh` copies `pmaports/` and `patches/kernel/` into the pinned
pmaports checkout and refreshes the checksums, then copies the APKBUILDs back so the
tracked files always carry the right sums. After changing a patch, run it and commit the
`pmaports/` change with it.

Packages end up in `.build/pmb-work/packages/v26.06/aarch64/`. They are signed with the
local key `pmos@local-6adf4a39` (public half in `pmaports/keys/`). **Back up the private
key** (`.build/pmb-work/config_abuild/`): if it is regenerated, every installed phone stops
trusting new packages. Installed images already carry the public key.

## Verifying a build

1. `scripts/check-kernel-config.sh` – static config checks.
2. RAM boot, no flash: `fastboot boot .build/images/boot.img` on a phone that already holds the
   matching rootfs (the image names the root by UUID).
3. `ssh <phone> 'sh -s' < tests/kernel-smoke.sh` – 20 on-device checks (display, USB, thermal,
   watchdog, idle, charger, Wi-Fi, Bluetooth, GPU node, VPN module). The Wi-Fi PCIe check
   fails on about 1 boot in 8 (known issue); re-run it after a reboot before blaming the kernel.

## Updating a running phone

The phone trusts our key, so a normal `apk` upgrade works. This changes the root
filesystem and stages `/boot/boot.img`; it does not change what the bootloader loads.

Copy the three packages from `.build/pmb-work/packages/v26.06/aarch64/` to the phone and
install them (this path is not yet tested end to end on a real phone):

```
scp linux-postmarketos-qcom-msm8996-*.apk device-xiaomi-gemini-*.apk \
    device-xiaomi-gemini-nonfree-firmware-*.apk <phone>:
ssh <phone> sudo apk add ./linux-postmarketos-qcom-msm8996-*.apk ./device-xiaomi-gemini-*.apk \
    ./device-xiaomi-gemini-nonfree-firmware-*.apk
```

Writing the Android `boot` partition is a separate, explicit step on the phone:

```
sudo gemini-boot-update            # shows image vs partition hashes, writes nothing
sudo gemini-boot-update --yes      # backs up the partition, writes, reads back and compares
sudo reboot
```

`gemini-boot-update` only ever touches `/dev/disk/by-partlabel/boot`, keeps a full backup in
`/var/lib/boot-backup/`, restores it automatically if the read-back differs, and refuses an
image that is not an Android boot image or does not fit the partition.

Note: until the new packages are installed, the `/boot/boot.img` on a phone built before
this change carries the JDI board file and would leave the display dead. Always install
the new packages first and check the dry-run output.

## Rollback

* Boot partition: `sudo gemini-boot-update --restore /var/lib/boot-backup/boot-<stamp>.img --yes`
  from a working system.
* If the phone does not come up: from fastboot, `fastboot flash boot <known-good boot.img>`
  (for example the image you flashed originally).
  `fastboot boot` of a known-good image works without flashing anything.
* Packages: `apk add linux-postmarketos-qcom-msm8996=<old version>` from the cached `.apk`,
  then `gemini-boot-update`.

Never touch `aboot`, `xbl`, `persist`, `modemst`, `fsg` or the GPTs, and never relock the
bootloader.

## Known limits

* `uname -r` is `6.19.5` for every build, so the modules directory does not change between
  kernel builds. A boot partition from one build with modules from another works only because
  the config is the same; always update both together.
* The LG Display board file is the default. A JDI-panel unit needs
  `deviceinfo_dtb="qcom/msm8996-xiaomi-gemini"` in the device package.
* The Wi-Fi PCIe link failure (about 1 boot in 8) is not fixed in the kernel; `wifi-guard`
  reboots around it.
* The server configuration in `rootfs-overlay/` (services, `battery-mode`, SSH policy) is
  not yet an apk; it is applied when the image is built.
