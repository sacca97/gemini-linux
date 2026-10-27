# Bring-up findings (2026-10-27)

Status: **flashed** (boot + userdata) and runs as a headless
server: SSH over USB and Wi-Fi, NetworkManager, deep CPU idle, thermal sensing,
a hardware watchdog, and a switchable battery bypass. Evidence comes from
`fastboot boot` runs read back through ramoops/pstore and from the live system.

## Flashed images

Flashed with `fastboot flash boot` and `fastboot flash userdata` only; `aboot`, `xbl`,
`persist`, `modemst`, `fsg` and the GPTs were not touched. Production cmdline, no
debug arguments, no `cpuidle.off`.

## How the evidence was collected

- The bootloader (LK) injects a `ramoops@92900000` node, so a stock-DTB kernel
  logs the whole boot into that 1 MiB RAM region. After a hang, a reset to
  fastboot followed by a boot of any kernel with pstore/ramoops enabled
  exposes the previous kernel's log in `/sys/fs/pstore/console-ramoops-0`.
  A long power-button hold is a full PMIC reset and wipes this log.
- Adding a second ramoops node makes ramoops probe twice and the second probe
  steals the console zone. Do not do that.
- From a running system, `sudo` + `reboot(RESTART2, "bootloader")` returns to
  fastboot with no key combination:
  `python3 -c 'import ctypes; ctypes.CDLL(None).syscall(142,0xfee1dead,672274793,0xA1B2C3D4,b"bootloader")'`.
  **Run `sync` first**: a raw reboot syscall lost a freshly written file once.
- A RAM-booted kernel leaves the stale fastboot picture on the panel, so verify
  over USB networking, not on screen.
- Tools: `scripts/sync-pmaports.sh`, `scripts/make-images.sh`.

## Root causes and fixes

| Symptom | Root cause | Fix |
|---|---|---|
| Silent total hang at 0.864 s after RPM regulators | PSCI idle: mainline defines one state (`standalone-power-collapse`) without `local-timer-stop`, but the per-CPU arch timer stops in power collapse | `patches/kernel/0004` adds `local-timer-stop`; `CONFIG_ARM_PSCI_CPUIDLE=y` (running governor: `menu`; TEO is built in). Idle test: 4 cores spent ~98 % of idle time in state1 and survived a load soak. Previously worked around with `cpuidle.off=1`. |
| Hang at ~24 s in `clk_propagate_rate_change` | Seen only with the old cpuidle/clock state | No longer reproduced; cpufreq works (idle 307-422 MHz, up to 1.59/2.15 GHz) |
| No USB gadget (`QUSB2PHY pll lock failed`) | PHY initialised before UFS is up | `patches/kernel/0005` (USB PHY reference clock). The stock initramfs works with it (see `docs/kernel.md`) |
| Initramfs stuck ~60 s | JDI panel module waits for a panel the unit does not have | LGD TD4322 driver (`0007`) and a separate board file `msm8996-xiaomi-gemini-lgd.dts` (`0008`) |
| Wi-Fi took ~200 s | `FW_LOADER_USER_HELPER_FALLBACK` waits 60 s per missing firmware file | Fallback disabled in the kernel config |
| Kernel WARN `sram_requests=-1` in `qcom_fg_sram_read` | `qcom_fg` registered the power supply before initialising its SRAM state | `0001` |
| WLED OVP IRQ enabled twice | Driver bug | `0002` |
| No watchdog | No node in the DTS | `0003` adds `qcom,kpss-wdt`; `watchdogd` pets `/dev/watchdog0` |
| `sudo` refused ("/etc must be owned by root") | `cp -a` of the overlay stamped uid 1000 on `/`, `/etc`, `/usr` | `make-images.sh` extracts with `tar --owner=0` and prints an owner check |
| Root filesystem stayed 2.9 GB | `resize2fs` refuses to run unless the fs was recently `e2fsck -f`'d | `make-images.sh` runs `e2fsck -fy` |
| Screen never blanked | Console blank timeout is reset from 60 s to 300 s ~5 s after boot by something not identified | `screenwake.py` re-asserts 60 s every 10 s. The timeout is stable at runtime; only boot resets it. |
| Phone shut itself off under load | Most likely `thermal-guard` (booted with `androidboot.mode=charger` afterwards); the syslog is RAM only so it could not be proven | Guard now logs to `/var/lib/thermal-guard.log`, syncs, needs two bad readings, battery limit 55 C |

## Open issue: Wi-Fi PCIe link

`qcom-pcie 600000.pcie: Phy link never came up` happens on roughly 1 boot in 8
(sometimes more). The QCA6174 is then absent from the bus for the whole boot;
Bluetooth from the same chip (UART) still works. The same failure was reported
in 2022 (pmaports issue #1869).

Ruled out: the sleep clock `divclk4`, a 300 ms regulator startup delay, a bus
reset plus rescan, the reference clock gate, and a driver retry that power
cycles the endpoint and PHY (a patch that was safe but never recovered a natural
failure; dropped from the distribution series). `pcie-qcom` has
`suppress_bind_attrs`, so userspace cannot unbind and rebind it.

Mitigation: `wifi-guard` reboots if `0000:01:00.0` is missing 90 s after boot,
at most twice in a row (counter in `/var/lib/wifi-guard`). Not yet seen firing
on real hardware. A reboot fixes it about 90 % of the time.

## Hardware facts (this unit)

- Panel: **LGD TD4322** command-mode (`mdss_mdp.panel=...lgd_fhd_td4322_cmd`), not the JDI R63452 in the stock DTS. The touch controller is disabled.
- UFS: Toshiba THGLF2G9J8LBATRH; `userdata` is ~54.8 GiB; `/` is 52.6 GB after the initramfs resize.
- Charger: `qcom-smbchg` (PMI8994). On a PC USB port it reports SDP with a 500 mA input limit. DCP / 3 A behaviour needs a wall charger test.
- GPU: Adreno 530. The firmware load at 4.6 s fails (initramfs has no firmware), but it loads fine on first use once the rootfs is up. Rendering has not been tested.
- Display: only ~5 `pp done time out, lm=2` messages per boot (at boot, 3 when the panel blanks, 1 on wake). Harmless; the command-mode panel misses its frame-done signal across on/off transitions.
- DSPs: `adsp` and `slpi` run and are unused on a headless server. Stopping them saved only ~1-2 C and ~7 mA, so it is not automated. The modem stays offline.
- Camera and audio modules are blacklisted from autoload (`/etc/modprobe.d/headless-blacklist.conf`); remove lines to re-enable.
- Wi-Fi: QCA6174 on PCIe, `ath10k`, fallback `board.bin`. Regulatory domain FR, power save off.
- Access: `ssh sacca@172.16.42.1`; the password is in `.build/credentials/user-password.txt` and also works for `sudo`. SSH password login is enabled in the overlay as a temporary measure. After each flash, remove the stale host key: `ssh-keygen -f ~/.ssh/known_hosts.gemini -R 172.16.42.1`.

## Battery bypass

`patches/kernel/0009` adds the standard `charge_behaviour` property (`auto`,
`inhibit-charge`) to `qcom-smbchg`. It clears `CHG_EN_BIT` in `BAT_IF_CMD_CHG`,
re-applies on USB source detect, and reports "Not charging". JEITA, termination
and thermal shutdown are untouched. It defaults to `auto` on every boot.

On a 500 mA SDP port, inhibit holds the battery level while the cable carries
the idle load; under a 4-core load the battery supplied ~1.2 A on top of the
input and sagged from 3.97 V to 3.68 V.

`battery-mode [status|auto|bypass|limit LOW HIGH]` (root to change) persists the
mode in `/etc/conf.d/battery-mode`. The `battery-mode` service enforces it every
30 s: `bypass` charges again below `FLOOR` (20 %) until `FLOOR+10`; `limit`
holds the battery between LOW and HIGH. Stopping the service restores `auto`.

## Services and settings in the overlay

`screenwake` (any key wakes the screen, the power key toggles it, blank timeout
60 s), `watchdogd`, `thermal-guard` (poweroff above 55 C battery / 95 C CPU,
log in `/var/lib/thermal-guard.log`), `battery-mode`, `wifi-guard`, `savetime`
(keeps the clock from restarting at 1970 before chrony steps it), `cpucap`
(big cluster capped at 1.55 GHz via `/etc/conf.d/cpucap`).

## Not done / untested

- Soak: days of idle with deep idle enabled. The old hang was probably an idle bug; one load soak is not proof.
- DCP / 3 A charging with a wall charger (follow `tests/charging.md`).
- `wifi-guard` on a real link failure.
- GPU rendering, USB host-mode Ethernet.
- The patch `0004` (`local-timer-stop`) is validated on this unit only.
- Upstream candidates, if wanted: `0007` (panel), `0001` and `0002` (small fixes), `0003` (watchdog, check timeouts), `0009` (charge_behaviour). See the readiness table in `docs/kernel.md`.
