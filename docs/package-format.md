# Package format

## USB payload

The builder writes this layout to `dist/opencmu-usb/`:

```text
/
├── bootstrap.sh
├── install.sh
├── manifest.env
├── jci-autoupdate
├── lib/
├── tweaks/
├── app/
└── SHA256SUMS
```

Copy the contents (not the directory) to the root of a FAT32/MBR USB drive.
`jci-autoupdate` is an empty marker file; it tells the updater that the drive
carries a payload. The exact trigger behavior depends on the firmware and is
not guaranteed by OpenCMU.

## manifest.env

| Key | Meaning |
| --- | --- |
| `MANIFEST_SCHEMA` | Must be `1`. |
| `PROJECT_NAME` | Display name. |
| `PROJECT_VERSION` | Payload version. |
| `FIRMWARE_MIN` | Lowest accepted `JCI_SW_VER`. |
| `FIRMWARE_MAX` | Highest accepted `JCI_SW_VER`. |
| `DEFAULT_TWEAKS` | Space-separated ids used when `--tweaks` is absent. |

The manifest is sourced as shell. Keep values quoted and free of command
substitution.

## tweak.env

| Key | Meaning |
| --- | --- |
| `TWEAK_NAME` | Human-readable name. |
| `TWEAK_RISK` | `low`, `medium`, or `high`. |
| `TWEAK_DESCRIPTION` | One-line explanation. |
| `TWEAK_EXPERIMENTAL` | `1` requires `--experimental`. |

## Receipts

`receipt.env` is shell-readable:

```sh
PROJECT="OpenCMU"
VERSION="0.1.0"
INSTALLED_AT=2026-01-01T00:00:00Z
FIRMWARE="74.00.324"
BACKUP_DIR="/data/opencmu/backups/20260101-000000-1"
TWEAKS="00-example"
```

Values are quoted so a multi-tweak plan (`TWEAKS="00-example 60-copy"`) can be
sourced safely during rollback.

`receipt.json` carries the same fields plus `backup_dir` and is what the
dashboard reads.

## Integrity

`builder/build-usb.sh` writes `SHA256SUMS` over every payload file. Verify it
before copying to a USB:

```sh
sh builder/verify-usb.sh dist/opencmu-usb
```

`verify-usb.sh` checks both the hashes and the file list, so an extra file added
to the USB after the build is reported. This detects corruption and accidental
changes, not an attacker who can rewrite `SHA256SUMS` too.

## The `.up` file (experimental)

`builder/make-up.py` writes a ZIP archive with two INI files:

```text
main_instructions.ini
versions.ini
```

`main_instructions.ini` requests one step:

```ini
[Instructions]
Count = 1
1 = Execute, "bootstrap", "execute.ini", 1
```

`versions.ini` declares a `JCI_SW_VER` compatibility label and a display
version. The builder exposes `--min-firmware`, `--display-version`, and
`--platform`; adjust them only after checking the labels on the target unit.

The `PackageID` is derived from `versions.ini` by default, so repeated builds
with the same inputs are byte-identical. Pass `--random-id` only when you
deliberately need a unique id.

### Why this is experimental

- The updater's signature checks and instruction parser are not documented.
- The package produced here is unsigned. Some firmware rejects unsigned `.up`
  files; some may accept them. Both outcomes are untested.
- OpenCMU deliberately does **not** use the command-injection filename technique
  seen in other packages. That technique is a security bug, not a feature.

Treat `dist/opencmu.up` as a bench-only artifact. The supported path is the USB
payload plus `bootstrap.sh`.
