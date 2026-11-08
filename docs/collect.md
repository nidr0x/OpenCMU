# Collecting stock files

OpenCMU ships a separate, read-only payload that copies a whitelist of stock
firmware files from the unit to a USB drive. It exists so a tweak can be written
against the real files instead of a guess.

It is **not** part of the installer and it is not needed to apply a tweak.

## What it does and does not do

Does:

- copy a fixed list of paths (`builder/collect.files`) to `opencmu-dump/`,
- record a SHA-256 and a size for each file,
- record `MISSING` for every whitelisted path the unit does not have,
- write `listing-jci.txt`, `system.txt`, `collect.log`, and `DONE`.

Does not:

- mount, remount, or unmount anything,
- delete or modify any file on the unit,
- execute anything from the unit,
- read the VIN, the navigation SD card, or user data,
- open a network connection.

The whitelist is code and configuration only: the JS/CSS the tweaks patch, the
service manifests, the firewall and speed-restriction scripts, and the version
file.

## Why the `.up` name looks like that

The payload runs through the factory updater, which evaluates the `.up` filename
as part of its package scan. The filename is therefore a shell command that
finds the mounted USB carrying the `.opencmu-collect` marker and runs its
`bootstrap.sh`.

This is the same class of technique third-party packages use, and it is the only
on-unit trigger known to work on this hardware without a signed package. It
carries real risk: anything that evaluates that filename runs as root.

That is why it lives in `builder/build-collect.sh`, out of `make dist`, and why
the installer never uses it.

## Build

```sh
make collect
```

Output: `dist/opencmu-collect/`.

## Run

1. Format a USB drive as FAT32 with an MBR partition table.
2. Copy the **contents** of `dist/opencmu-collect/` to the root of the drive.
   The root must contain `bootstrap.sh`, `collect.sh`, `files.txt`,
   `.opencmu-collect`, and the `.up` file.
3. With the ignition on, insert the drive in a media USB port.
4. Wait until the unit is idle, then remove the drive.
5. Check that `opencmu-dump/DONE` exists.

If `opencmu-dump/` does not appear, the trigger did not run. Nothing on the unit
was changed and the drive is reusable.

## Send back

`opencmu-dump/` contains:

```text
opencmu-dump/
├── DONE
├── collect.log
├── system.txt
├── listing-jci.txt
├── manifest.txt
└── files/<original absolute path>
```

`manifest.txt` is the index: `sha256  size  path`, or `MISSING  path`. The unit
has no `sha256sum`, so the collector uses `openssl dgst -sha256` there; if only
`md5sum` is available the hash is prefixed `md5:`.

## What to do with the result

A tweak that patches a stock file needs three things from the dump: the exact
literal to anchor on, the number of times it occurs, and the replacement. With
the real file those become facts instead of assumptions, and the tweak can ship
with a verified anchor.

Files in the dump are stock firmware content. They are not redistributable, so
keep them out of the repository. `dist/` is already gitignored; put the dump
there if you need somewhere to stage it.
