# OpenCMU

**Reversible, open-source tweaks for Gen 6 Mazda Connect (MZD Connect).**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status: alpha](https://img.shields.io/badge/status-alpha-orange.svg)](#status)
[![Platform: Gen 6 Mazda Connect](https://img.shields.io/badge/platform-MZD%20Connect%20(Gen%206)-informational.svg)](#compatibility)

OpenCMU is a clean-room toolkit for applying small, reversible changes to the
first-generation Mazda Connect head unit — the 7-, 8-, and 9-inch JCI/Visteon
CMU commonly called **MZD Connect** or **Gen 6 Mazda Connect**.

It is not a firmware replacement, not a jailbreak, and not a redistribution of
someone else's package. It is a manifest, a POSIX shell installer, a set of
optional tweaks, and a static dashboard. Every change is backed up, recorded,
and can be rolled back.

> [!WARNING]
> **Alpha software. Bench testing only.** OpenCMU has not been validated on a
> real CMU. The supported target is firmware **v74.00.324**. Do not install it
> on a daily-driven car until the exact payload has been tested on a bench unit
> with the same firmware and a recovery path is in place.

---

## Table of contents

- [Why OpenCMU](#why-opencmu)
- [What it does](#what-it-does)
- [What it does not do](#what-it-does-not-do)
- [Compatibility](#compatibility)
- [How it works](#how-it-works)
- [Quick start](#quick-start)
- [Installing on a car](#installing-on-a-car)
- [Command-line reference](#command-line-reference)
- [Tweaks](#tweaks)
- [Dashboard](#dashboard)
- [Build and test](#build-and-test)
- [Collecting stock files](#collecting-stock-files)
- [Safety](#safety)
- [Recovery](#recovery)
- [Project layout](#project-layout)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

---

## Why OpenCMU

Most CMU tweak packages are opaque: a signed blob, a closed installer, a license
check, and no way to see what changed. OpenCMU takes the opposite approach.

- **Reversible by default.** Every file is backed up before it is touched. A
  receipt and a journal make rollback possible even after a failed run.
- **Auditable.** The installer is POSIX `sh`. You can read every line that runs
  as root.
- **No VIN binding.** There is no VIN check, no license server, no activation,
  and no phone-home. OpenCMU does not implement those mechanisms at all.
- **Clean-room.** No code, binaries, themes, fonts, or text from proprietary
  packages. See [CONTRIBUTING.md](CONTRIBUTING.md).
- **Boring on purpose.** No daemon, no network service, no bootloader changes,
  no kernel changes, no recovery-partition changes.

## What it does

| Capability | Detail |
| --- | --- |
| Manifest-driven install | `manifest.env` declares the payload version, firmware range, and default tweaks. |
| Dry-run first | Nothing changes unless you pass `--apply`. |
| Firmware guard | Refuses to run outside the declared `JCI_SW_VER` range. |
| Timestamped backups | Original files are copied under `/data/opencmu/backups/`. |
| Receipts | `receipt.env` and `receipt.json` record what was installed, when, and where the backup is. |
| Journaled rollback | Tweak ids are recorded before they run, so a crash mid-tweak is still recoverable. |
| Reverse-order rollback | Tweaks are undone in the opposite order they were applied. |
| Experimental gate | High-risk tweaks require `--experimental` and a per-tweak config file. |
| Anchored patching | Firmware tweaks replace exact literals or append marked blocks, and abort on a mismatched anchor. |
| USB builder | Produces a verified `dist/opencmu-usb/` payload with `SHA256SUMS`. |
| Dashboard | A static ES5 page that reads the install receipt. No external assets. |

## What it does not do

- It does not replace or modify the CMU firmware.
- It does not touch the bootloader, kernel, or recovery partition.
- It does not bypass VIN, license, or payment checks.
- It does not phone home or require an internet connection.
- It does not bundle third-party binaries. The Android Auto touch shim is
  AGPL-3.0 code from another project; tweak 58 installs a copy you provide and
  never ships one.
- It does not guarantee that a tweak works on your region, trim, or firmware.

Nothing in the bundled set is applied by default except the marker tweak.
Tweaks that change services or boot behaviour are marked experimental and need
`--experimental`; the small GUI patches are not. None of them has been run on a
real unit yet.

## Compatibility

Compatibility has two parts, and both must match:

1. **The car has a Gen 6 Mazda Connect CMU.** This is the first-generation
   JCI/Visteon unit with the rotary commander and the tile-based interface. It
   shipped with 7-, 8-, and 9-inch screens depending on model and market.
2. **The unit runs firmware v74.00.324.** The region suffix (`NA N`, `EU N`,
   `4A N`, `JP M`) does not change the installer's decision; it checks the
   `JCI_SW_VER` value.

A model year only tells you that a car is a **candidate**. Mazda introduced and
retired this system on different schedules by country, and sometimes sold the old
and new systems side by side by trim. The About screen is authoritative.

### Candidate models

| Model | Chassis | Candidate years | Notes |
| --- | --- | --- | --- |
| Mazda2 / Demio | DJ, DL | 2014–present* | Exclude the Toyota-built hybrid and trims without a center screen. |
| Mazda3 / Axela | BM, BN | late 2013–2018 | The 2019 BP moved to the newer system. |
| Mazda6 / Atenza | GJ, GL (facelift) | 2015–2025 | Early cars can have a TomTom unit instead. |
| CX-3 | DK | 2015–present* | Endpoint depends on market and trim. |
| CX-4 | — | 2016–unknown | China only; not confirmed. |
| CX-5 | KE facelift, KF | 2015–2025* | US 2021+ is the newer system; other markets vary by trim. |
| CX-8 | KG | 2017–2022* | Market and trim dependent. |
| CX-9 | TC | 2016–2023* | Market and trim dependent. |
| MX-5 / Roadster | ND | 2015–2023* | 2024+ cars use the newer 8.8-inch system in NA, Europe, Japan, and Australia. |
| Fiat / Abarth 124 Spider | — | 2016/17–2020 | Not confirmed. |

`*` means the original-style interface was still offered in at least one market
after the main production run. It does not mean every car in that market has it.

This table was compiled from Mazda launch records and service bulletin
**09-018/22**. Model years vary by market; treat them as a starting point, not a
promise.

### Not supported

- **Mazda3 BP** (2019+) and anything on the newer Mazda Connect platform.
- **CX-30, MX-30, CX-50, CX-60, CX-70, CX-80, CX-90** — newer system from launch.
- **MX-5 ND** model year 2024+ in North America, Europe, Japan, and Australia.
- Any unit whose About screen does not report **v74.00.324**.
- Units with a TomTom navigation system instead of Mazda Connect.
- Toyota-built Mazda2 Hybrid variants.
- CX-4 and Fiat/Abarth 124 Spider: treat as unconfirmed.

### Check your firmware

On the unit:

1. Open **Settings → System → About → Version Information**.
2. Read **OS Version**, **Region**, and **Failsafe Version**.
3. Compare the OS version with **74.00.324**.

Example:

```text
OS Version:       74.00.324A
Region:           NA N
Failsafe Version: 59.00.504
```

If the menu is unavailable, the diagnostic keypad usually works: hold
**Volume/Mute + Music + Favorites** for about three to five seconds, then enter
**53**. Code **99** starts a firmware-update search — do not use it to read the
version.

Region labels differ by market (`74.00.324A NA N`, `74.00.324 EU N`,
`74.00.324 4A N`, `74.00.324 JP M`). The installer compares the numeric
version, not the region string. It does not cross-flash regions and neither
should you.

> [!NOTE]
> OpenCMU ships with `FIRMWARE_MIN` and `FIRMWARE_MAX` both set to `74.00.324`.
> Widen the range only after testing the exact build on a bench unit.

## How it works

```text
USB payload
   │
   ├── bootstrap.sh ──► install.sh
   │                       │
   │                       ├── load manifest.env
   │                       ├── check /jci/version.ini (JCI_SW_VER)
   │                       ├── dry-run? ──► print plan, stop
   │                       │
   │                       ├── create state + backup dirs
   │                       ├── write receipt (provisional)
   │                       ├── for each tweak:
   │                       │     ├── journal id in installed.list
   │                       │     ├── source apply.sh
   │                       │     └── abort on error
   │                       └── rewrite receipt (final)
   │
   └── app/ ──► static dashboard reading receipt.json
```

State lives under `/data/opencmu/`:

```text
/data/opencmu/
├── state/
│   ├── installed.list     tweak ids, journaled before each apply
│   ├── receipt.env        shell-readable install record
│   └── receipt.json       dashboard-readable install record
├── backups/
│   └── <timestamp>-<pid>/ original files, keyed by absolute path
└── logs/
```

Design rules:

- **Dry-run is the default.** `--apply` is required for install and rollback.
- **The receipt is written before the first tweak.** A partial run is still
  rollbackable.
- **The id is journaled before `apply.sh` runs.** Rollback scripts must be safe
  no-ops when their tweak never ran.
- **Writes are atomic.** Content goes to a same-directory temporary file, is
  synced, then renamed. Symlinked targets are rejected.
- **Backups and restores reject symlinks too.**
- **A second apply is refused** while a receipt exists; roll back first.
- **Rollback refuses to guess.** If the journal is empty but the backup directory
  contains files, it stops and asks for manual inspection.

## Quick start

Host only, no car:

```sh
git clone https://github.com/<your-user>/opencmu.git
cd opencmu

make test     # smoke test against a temporary fake root
make dist     # build dist/opencmu-usb and dist/opencmu.up
```

`make test` never touches a real CMU. It creates a fake root, installs the
example tweak, checks the receipt and backup, rolls it back, and exercises the
firmware guard, the experimental gate, partial-failure recovery, and the
builders.

Verify the USB payload before copying it:

```sh
sh builder/verify-usb.sh dist/opencmu-usb
```

## Installing on a car

> [!WARNING]
> The on-unit trigger is **not yet validated on hardware**. The payload is
> designed to be launched by the factory USB update flow through
> `bootstrap.sh` and the `jci-autoupdate` marker. Test the flow on a bench unit
> before trusting it in a car.

### 1. Prepare the USB

- Use a FAT32 drive with an MBR partition table.
- Copy the **contents** of `dist/opencmu-usb/` to the root of the drive, not the
  directory itself.
- The root should contain `bootstrap.sh`, `install.sh`, `manifest.env`,
  `jci-autoupdate`, `lib/`, `tweaks/`, `app/`, and `SHA256SUMS`.

### 2. Plan first

On a bench unit, or with a fake root:

```sh
sh install.sh --usb /path/to/payload --root /mnt/cmu
```

Without `--apply`, the installer prints the plan and changes nothing.

### 3. Apply

```sh
sh install.sh --usb /path/to/payload --root /mnt/cmu --apply
```

Keep the ignition on and the USB connected until the unit is idle again.

### 4. Verify

Check that the marker, receipt, and backup exist:

```sh
cat /data/opencmu/state/receipt.env
ls /data/opencmu/backups/
```

### 5. Roll back

```sh
sh install.sh --usb /path/to/payload --root /mnt/cmu --rollback
sh install.sh --usb /path/to/payload --root /mnt/cmu --apply --rollback
```

Keep the original USB: rollback needs the same `tweaks/<id>/rollback.sh` files.

## Command-line reference

| Flag | Meaning |
| --- | --- |
| `--usb PATH` | Payload directory. Defaults to the installer's directory. |
| `--root PATH` | Target root. Defaults to `/`. Use a fake root for testing. |
| `--apply` | Actually change files. Without it, the installer is a dry run. |
| `--dry-run` | Print the plan only. This is the default. |
| `--rollback` | Restore the last receipt's backup. Needs `--apply` to act. |
| `--tweaks "A B"` | Space-separated tweak ids. Defaults to `DEFAULT_TWEAKS`. |
| `--list` | List available tweaks and exit. |
| `--experimental` | Allow tweaks marked `TWEAK_EXPERIMENTAL=1`. |
| `--force` | Allow a missing `/jci/version.ini`. Bench roots only. |
| `-h`, `--help` | Show help. |

Examples:

```sh
sh install.sh --list
sh install.sh --apply --tweaks "00-example"
sh install.sh --apply --experimental --tweaks "32-shorter-delay 36-opera-cache-increase"
sh install.sh --apply --rollback
```

## Tweaks

A tweak is a directory under `tweaks/`:

```text
tweaks/30-my-tweak/
├── tweak.env      name, risk, description, experimental flag
├── apply.sh       sourced by the installer
└── rollback.sh    sourced during rollback
```

Bundled tweaks:

| Id | Risk | Default | What it does |
| --- | --- | --- | --- |
| `00-example` | low | yes | Writes a marker under `/data/opencmu` to prove the pipeline works. |
| `30-no-disclaimer` | high | no | Acknowledges the boot disclaimer without a tap. |
| `31-no-reverse-warning` | medium | no | Blanks the safety text in the reverse camera app. |
| `32-shorter-delay` | low | no | Shortens the list scroll delay and autoscroll interval. |
| `33-no-gracenote-text` | low | no | Drops the Gracenote label on the now-playing screen. |
| `34-bigger-album-art` | low | no | Enlarges the now-playing artwork. |
| `35-usb-audio-mod` | low | no | Larger USB audio transport buttons with a focus ring. |
| `36-opera-cache-increase` | low | no | Enables the Opera disk cache and raises it from 2000 KB to 8000 KB. |
| `37-mute-pause` | low | no | Remaps the steering-wheel mute button to play/pause. |
| `38-order-audio-sources` | medium | yes | Rebuilds the entertainment source list with the preferred sources first; set `OPENCMU_AUDIO_ORDER` to a comma-separated list of stock source IDs (see `docs/tweaks.md` for the full 74.00.324 list). Reorders the list only; it never selects a source. |
| `40-menu-loop` | low | no | Makes the home menu wrap at both edges. |
| `41-list-loop` | low | no | Makes long lists wrap at both ends. |
| `42-no-beeps` | low | no | Silences the interface beep. |
| `43-touch-while-driving` | high | no | Keeps the touchscreen usable while moving. |
| `44-track-notification` | low | no | Shows artist and title in USB audio track notifications. |
| `45-carplay-autoforeground` | medium | no | Raises CarPlay as soon as a phone session starts. |
| `46-disable-siriusxm` | high | no | Switches off the SiriusXM services. |
| `47-disable-pandora` | high | no | Switches off the Pandora service; leaves the shared streaming server to 49. |
| `48-disable-stitcher` | high | no | Switches off the Stitcher service; leaves the shared streaming server to 49. |
| `49-disable-internet-radio-servers` | high | no | Switches off the two streaming servers. |
| `50-disable-aha` | high | no | Switches off Aha Radio and re-points the stages that wait on it. |
| `51-fix-websocket-msg-ordering` | medium | no | Exposes the two stack helpers in `Websockets.js` as prototype methods. |
| `52-dlt-logging-reduction` | low | no | Shrinks the DLT buffer and stops the timed flush in `/etc/dlt.conf`. |
| `53-skip-startup-animation` | high | no | Switches off the `tranlogo` service that plays the boot animation. |
| `54-wifi-boot-off-busy-core` | high | no | Pins `start_wifi`, `NMS_svc` and `blm_nms_svc` to the second CPU core. |
| `55-carplay-engine-off-busy-core` | high | no | Pins `jciCARPLAY` to the second CPU core. |
| `56-disable-offboard` | high | no | Switches off the off-board service named in `OPENCMU_OFFBOARD_SERVICE`. |
| `57-firewall-iptables-restore` | high | no | Adds a one-call `iptables-restore` fast path to `jci-fw.sh`. Needs a ruleset and an anchor. |
| `58-install-aatouch` | high | no | Installs a user-supplied Android Auto touch shim under `/data_persist`. |
| `59-enable-aa-touch` | high | no | Declares the AA touchscreen and preloads the shim. |
| `60-startup-hook` | high | no | Runs `*.sh` from `/data/opencmu/boot.d` at boot, in the background. |
| `61-keep-cluster-compass` | high | no | Mirrors the navigation service and sends the touch speed override while it runs. Needs `60-startup-hook`. |
| `62-disable-touchscreen` | high | no | Re-asserts `SpeedRestriction(1)` at boot so the touchscreen stays locked. Needs `60-startup-hook`. |
| `63-no-blank-art` | low | no | Restores the artwork frame class when a new image path arrives. |
| `64-disable-jcicd` | high | no | Switches off the CD service. |
| `65-disable-dvd` | high | no | Switches off the DVD service. |
| `66-disable-tv` | high | no | Switches off the TV service. |
| `67-disable-dab` | high | no | Switches off the DAB service. |
| `68-disable-voice` | high | no | Switches off voice recognition. |
| `69-disable-traffic` | high | no | Switches off the traffic service. |
| `70-disable-diagnostics` | high | no | Switches off `jciTestDiag` and `kapture`. |
| `71-disable-telematics` | high | no | Switches off the six telematics services. Do not use where eCall/SOS is required. |
| `72-disable-nav` | high | no | Switches off navigation. The cluster compass may need 61 after this. |
| `73-disable-jvmm` | high | no | Switches off the JVMM voice-memory service. |
| `74-earlier-wifi-init` | high | no | Waits up to 10 s for `wlan0` before `start_wifi.sh` loads the modules. |
| `75-enable-ssh` | medium | no | Installs a key-only SSH config and starts sshd. Needs `OPENCMU_SSH_PUBKEY`. |
| `76-enable-wifi-client` | high | no | Switches Wi-Fi to client mode at boot. Needs an SSID and passphrase and `60-startup-hook`. |
| `77-boot-profiler` | low | no | Read-only runtime that logs when boot milestones are reached (HMI process, wlan0, hostapd, ready flag, CarPlay session). Needs `60-startup-hook`. |
| `78-select-bt-audio-first` | medium | no | Switches to Bluetooth audio once per boot when a device connects. |
| `90-replacement-template` | high | no | Generic template for replacing a user-supplied file. Ships no patch. |
| `91-touch-replacement` | high | no | Touch-lock template. Ships no patch. |

Most firmware tweaks edit one file through an anchored helper from
`installer/lib/patch.sh`: it replaces an exact literal, rewrites one keyed
number, or appends a marked block. If the anchor is missing or appears more than
once, the tweak aborts before writing. A second apply does not duplicate the
appended blocks.

The templates refuse to run without `--experimental` **and** a
`tweak.local.env`:

```sh
# tweaks/90-replacement-template/tweak.local.env  (gitignored)
TARGET_FILE=/path/on/the/unit
REPLACEMENT_FILE=/path/on/the/usb/patched-file
EXPECTED_SHA256=<sha256 of the stock TARGET_FILE>
```

The installer backs up the target, verifies the stock hash, confirms the target
did not change during the backup, and only then replaces it atomically.

Several tweaks need an input the project cannot ship, and refuse to run
without it:

```sh
# 57-firewall-iptables-restore
#   OPENCMU_WCP_RULES: an iptables-save ruleset for the WCP interface
#   OPENCMU_FW_ANCHOR: the exact opening line of the firewall function in
#   /jci/scripts/jci-fw.sh, for example "firewall_start() {"
OPENCMU_WCP_RULES=./wcp.rules OPENCMU_FW_ANCHOR='firewall_start() {' \
  sh install.sh --apply --experimental --tweaks 57-firewall-iptables-restore

# 58-install-aatouch
#   OPENCMU_AATOUCH_SHIM: the libpatch-blmjciaapa.so you provide
#   OPENCMU_AATOUCH_SHA256: its digest, so the tweak installs exactly that file
OPENCMU_AATOUCH_SHIM=./libpatch-blmjciaapa.so \
OPENCMU_AATOUCH_SHA256=<sha256> \
  sh install.sh --apply --experimental --tweaks 58-install-aatouch 59-enable-aa-touch

# 75-enable-ssh
#   OPENCMU_SSH_PUBKEY: one ssh-rsa public key; OpenSSH 5.9 cannot use ed25519
#   OPENCMU_SSH_START=0: install the config without starting sshd (optional)
#   The tweak does not change firewall rules; make sure the port is reachable.
OPENCMU_SSH_PUBKEY=./id_rsa.pub \
  sh install.sh --apply --experimental --tweaks 75-enable-ssh

# 76-enable-wifi-client
#   OPENCMU_WIFI_SSID and OPENCMU_WIFI_PSK are required
#   OPENCMU_WIFI_STATIC_IP, OPENCMU_WIFI_NETMASK and OPENCMU_WIFI_GATEWAY are
#   optional; without them the runtime uses udhcpc
OPENCMU_WIFI_SSID='garage' OPENCMU_WIFI_PSK='<passphrase>' \
  sh install.sh --apply --experimental --tweaks 60-startup-hook 76-enable-wifi-client
```

Tweak 59 also needs tweak 58 in the same run, or a shim already installed on the
unit: it declares `/dev/input/aa-touchscreen` and will not do so without the
device behind it.

Tweaks 61, 62, 76 and 77 install a boot runtime instead of editing a file, so
they need `60-startup-hook` first: that tweak creates `/data/opencmu/boot.d`
and starts its scripts at boot. They write nothing when the directory is
missing, and the installer itself never spawns the runtime.

See [docs/tweaks.md](docs/tweaks.md) for the full authoring guide and helper
reference, and [docs/boot-profiling.md](docs/boot-profiling.md) for the
procedure to profile a real boot with `77-boot-profiler` and turn the timeline
into tweak choices.

## Dashboard

`app/` is a static ES5 dashboard with no external fonts, images, or scripts. It
reads `state.json` (same shape as `receipt.json`) and shows the payload version,
firmware, install time, active tweaks, and backup path.

```sh
make dist
cd dist/opencmu-usb/app
python3 -m http.server 8080
# open http://localhost:8080
```

`make dist` seeds `app/state.json` from `app/state.example.json` so the page
renders before an install. The source tree only ships the example.

## Build and test

Requirements:

- POSIX `sh`, `awk`, `cp`, `mv`, `find`, `diff`
- `sha256sum`, `shasum -a 256`, or `openssl dgst -sha256` (the unit has no
  `sha256sum`; `openssl` is the fallback that works there)
- Python 3 for the experimental `.up` builder

```sh
make test    # smoke tests against a fake root
make dist    # USB payload + experimental .up
make clean   # remove dist/
```

`make dist` builds the USB payload, verifies `SHA256SUMS`, and then builds the
`.up`. The `.up` output is reproducible: the same inputs produce byte-identical
files.

The `.up` builder is experimental. It writes the updater's INI structure but
does **not** sign the package, and updater signature behavior is unverified. The
supported path is the USB payload with `bootstrap.sh`.

## Collecting stock files

Writing a new tweak needs the real stock file, not a guess. `make collect` builds
a separate read-only payload that copies a whitelist of firmware files to the
USB, with a SHA-256 manifest:

```sh
make collect
# output: dist/opencmu-collect/
```

It only reads from the unit. It does not mount, remount, delete, or execute
anything there, and it never touches the installer path.

The `.up` filename is a command injection evaluated by the factory updater. That
is how the payload runs at all, and it is why the collector is opt-in, lives
outside `make dist`, and is documented separately in
[docs/collect.md](docs/collect.md). Anything that evaluates that filename runs as
root.

## Safety

Read [docs/safety.md](docs/safety.md) before touching a car. The short version:

- Test on a bench unit with the same firmware first.
- Keep a stock recovery USB and a known-good payload.
- Do not touch the bootloader, kernel, or recovery partitions.
- Keep the ignition on and the USB connected until the unit is idle.
- Apply one tweak at a time, then verify.
- Keep `/data/opencmu/backups/`; it is your rollback source.

## Recovery

```sh
sh install.sh --rollback            # plan
sh install.sh --apply --rollback    # restore
```

If the installer cannot run, restore files manually from the receipt backup:

```sh
. /data/opencmu/state/receipt.env
ls "$BACKUP_DIR"
```

Each file is stored under the backup directory by its absolute path without the
leading slash. See [docs/recovery.md](docs/recovery.md) for the manual procedure
and the escalation path if the UI does not come back.

## Project layout

```text
opencmu/
├── app/                    static dashboard (ES5)
├── builder/
│   ├── build-usb.sh        assemble dist/opencmu-usb
│   ├── verify-usb.sh       check hashes and file list
│   ├── make-up.py          experimental .up builder
│   ├── build-collect.sh    read-only stock collector payload
│   ├── collect.sh          runs on the unit; copies the whitelist
│   └── collect.files       whitelist of stock paths
├── docs/
│   ├── architecture.md
│   ├── boot-profiling.md
│   ├── collect.md
│   ├── package-format.md
│   ├── recovery.md
│   ├── safety.md
│   └── tweaks.md
├── installer/
│   ├── bootstrap.sh        USB entrypoint
│   ├── install.sh          main installer
│   └── lib/                common, manifest, patch, tweaks
├── tests/
│   └── smoke.sh            fake-root integration tests
├── tweaks/
│   ├── 00-example/
│   ├── 30-no-disclaimer/
│   ├── 31-no-reverse-warning/
│   ├── 32-shorter-delay/
│   ├── 33-no-gracenote-text/
│   ├── 34-bigger-album-art/
│   ├── 35-usb-audio-mod/
│   ├── 36-opera-cache-increase/
│   ├── 37-mute-pause/
│   ├── 38-order-audio-sources/
│   ├── 40-menu-loop/
│   ├── 41-list-loop/
│   ├── 42-no-beeps/
│   ├── 43-touch-while-driving/
│   ├── 44-track-notification/
│   ├── 45-carplay-autoforeground/
│   ├── 46-disable-siriusxm/
│   ├── 47-disable-pandora/
│   ├── 48-disable-stitcher/
│   ├── 49-disable-internet-radio-servers/
│   ├── 50-disable-aha/
│   ├── 51-fix-websocket-msg-ordering/
│   ├── 52-dlt-logging-reduction/
│   ├── 53-skip-startup-animation/
│   ├── 54-wifi-boot-off-busy-core/
│   ├── 55-carplay-engine-off-busy-core/
│   ├── 56-disable-offboard/
│   ├── 57-firewall-iptables-restore/
│   ├── 58-install-aatouch/
│   ├── 59-enable-aa-touch/
│   ├── 60-startup-hook/
│   ├── 61-keep-cluster-compass/
│   ├── 62-disable-touchscreen/
│   ├── 63-no-blank-art/
│   ├── 64-disable-jcicd/
│   ├── 65-disable-dvd/
│   ├── 66-disable-tv/
│   ├── 67-disable-dab/
│   ├── 68-disable-voice/
│   ├── 69-disable-traffic/
│   ├── 70-disable-diagnostics/
│   ├── 71-disable-telematics/
│   ├── 72-disable-nav/
│   ├── 73-disable-jvmm/
│   ├── 74-earlier-wifi-init/
│   ├── 75-enable-ssh/
│   ├── 76-enable-wifi-client/
│   ├── 77-boot-profiler/
│   ├── 78-select-bt-audio-first/
│   ├── 90-replacement-template/
│   └── 91-touch-replacement/
├── manifest.env
├── Makefile
├── LICENSE
├── SECURITY.md
└── CONTRIBUTING.md
```

## FAQ

**Does it work on my 2021 CX-5?**
Maybe. US 2021+ CX-5 uses the newer system, but other markets kept the Gen 6
unit by trim. Check the About screen: if it does not report v74.00.324, it is
not supported.

**Does it work on a 2024 MX-5?**
No in North America, Europe, Japan, and Australia: those cars moved to the newer
8.8-inch system. Imports need country-specific evidence.

**Do I need internet access in the car?**
No. The payload is self-contained. There is no license server and no telemetry.

**Does it remove the warning screen?**
Not by default. `30-no-disclaimer` does it, is marked experimental, and needs
`--experimental`. It is a reversible text patch: rollback restores the original
file from the run backup.

**Can it brick my unit?**
Any change made as root carries risk. OpenCMU reduces it with dry-run, backups,
a journal, a firmware guard, and rollback — but it cannot eliminate it. Bench
test first.

**Why is the firmware range so narrow?**
Because that is the only build this payload has been written against. Widening
the range without hardware testing turns the guard into decoration.

**Is this a fork of ScreenTune or Miatafy?**
No. OpenCMU is an independent clean-room project. It contains no proprietary
code, binaries, themes, fonts, or text. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Contributing

Contributions are welcome if they are original work or permissively licensed.

- Read the clean-room policy in [CONTRIBUTING.md](CONTRIBUTING.md).
- Keep the installer POSIX `sh` and BusyBox-compatible.
- Add a test for every behavior change.
- State whether the change was tested on a real unit or only on a fake root.

Security reports: see [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).

OpenCMU is not affiliated with, endorsed by, or sponsored by Mazda, Miatafy,
ScreenTune, or MZD AIO. Mazda, MZD Connect, and related marks belong to their
respective owners. You are responsible for complying with local law and with
your vehicle's warranty terms.
