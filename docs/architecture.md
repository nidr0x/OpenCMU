# Architecture

OpenCMU is a payload plus a small installer. Everything runs as the user the
Mazda updater already uses (root on the CMU); there is no daemon, no network
service, and no background process left behind.

## Goals

- Apply small, reversible changes to user-space files.
- Make every change auditable and restorable.
- Refuse to run on firmware outside the declared range.
- Keep the payload readable: shell scripts, a manifest, and plain files.

## Non-goals

- Replacing the bootloader, kernel, recovery partition, or CMU firmware.
- Bypassing VIN checks, license servers, or paid packages.
- Persisting a privileged service.
- Obfuscating what the installer does.

## Components

```text
USB root
├── bootstrap.sh          entrypoint; locates the payload and calls install.sh
├── install.sh            argument parsing, firmware guard, receipt, rollback
├── manifest.env          schema, version, firmware range, default tweaks
├── lib/
│   ├── common.sh         logging, version compare, backup, atomic write
│   ├── manifest.sh       manifest loading and JCI_SW_VER guard
│   └── tweaks.sh         tweak discovery, apply, rollback
├── tweaks/<id>/
│   ├── tweak.env         name, risk, description, experimental flag
│   ├── apply.sh          sourced by the installer
│   └── rollback.sh       sourced during rollback
├── app/                  static dashboard (ES5, no external assets)
└── SHA256SUMS            integrity list for the payload
```

## Install flow

1. `bootstrap.sh` resolves its own directory and execs `install.sh`.
2. `install.sh` loads `manifest.env` and validates the schema.
3. `check_firmware` reads `/jci/version.ini` and compares `JCI_SW_VER` with
   `FIRMWARE_MIN` and `FIRMWARE_MAX`.
4. Without `--apply`, each selected tweak is only named; nothing is written.
5. With `--apply`, `ensure_state` creates the state and backup directories and
   checks free space.
6. Each tweak is sourced in a subshell with `set -eu`. A non-zero exit aborts
   the install immediately.
7. `write_receipt` stores `receipt.env` and `receipt.json`, and the applied ids
   are appended to `installed.list`.

## State layout

```text
/data/opencmu/
├── state/
│   ├── installed.list    started tweak ids, in order (journal)
│   ├── receipt.env       shell-readable install record
│   └── receipt.json      dashboard-readable install record
├── backups/<timestamp>-<pid>/<absolute path without leading slash>
└── logs/install.log      reserved
```

Backups keep the original file mode with `cp -p`. A `.created` marker inside a
backup directory lists files that did not exist before the install, so rollback
removes them instead of leaving orphans.

## Failure handling

- The receipt is written before the first tweak runs, and each tweak id is
  appended to `installed.list` before its `apply.sh` starts. A failure or power
  cut mid-tweak is therefore still journaled and can be rolled back.
- Rollback scripts must be safe no-ops when their tweak never ran.
- A tweak failure stops the run; the failing id stays journaled.
- Applying again while a receipt exists is refused until rollback completes.
- If `installed.list` is empty but the backup directory contains files,
  rollback refuses to clear the receipt and asks for manual inspection.
- Rollback runs in reverse order and refuses to continue if a tweak directory or
  its `rollback.sh` is missing. Keep the original USB.
- Writes go through a temporary file in the same directory and `mv`, so a
  partial write does not replace the target.
- Symlinked targets are rejected by `atomic_write`.

## Why shell

The CMU ships BusyBox `sh`, not Python or Node. A POSIX shell payload has no
runtime dependency beyond coreutils/BusyBox, is easy to audit line by line, and
can be exercised against a fake root on a laptop.
