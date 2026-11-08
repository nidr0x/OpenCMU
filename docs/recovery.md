# Recovery

## 1. Roll back with the installer

Keep the original USB. Rollback needs the same `tweaks/<id>/rollback.sh` files
that performed the install.

```sh
sh install.sh --root / --rollback            # plan only
sh install.sh --root / --apply --rollback    # restore
```

Rollback runs in reverse order, restores every backed-up file, removes files
the install created, and then clears `installed.list` and the receipt. The
backup directory is kept.

Each tweak id is journaled before its `apply.sh` runs, so rollback also covers a
run interrupted mid-tweak. If `installed.list` is empty while the backup
directory contains files, the installer refuses to clear the receipt and asks
for manual inspection instead of guessing.

## 2. Restore by hand

If the installer cannot run, restore from the receipt backup:

```sh
. /data/opencmu/state/receipt.env
ls "$BACKUP_DIR"
```

Each file is stored under the backup directory using its absolute path without
the leading slash. For example, `/jci/some/file` is backed up as
`$BACKUP_DIR/jci/some/file`.

```sh
cp -p "$BACKUP_DIR/jci/some/file" /jci/some/file
```

Check the `.created` file in the backup directory for paths that did not exist
before the install; those should be removed.

## 3. If the UI does not come back

- Power-cycle the unit once. Do not repeatedly cycle it.
- Try the stock recovery USB for the exact firmware.
- If the unit still boots to a blank or looping screen, stop and use dealer
  service. Do not apply another package hoping to overwrite the problem.

## 4. If the unit boots but a tweak misbehaves

1. Run `--rollback` with `--apply`.
2. Confirm the receipt is gone and the touched files match the backup.
3. Re-run the dry-run plan before trying anything else.

## 5. Logs and evidence

`/data/opencmu/logs/install.log` is reserved for installer output. Until the
installer writes to it, capture the console output yourself:

```sh
sh install.sh --apply 2>&1 | tee /data/opencmu/logs/install.log
```

When reporting a problem, include the firmware version, the tweak ids, the
receipt, and the exact command line. Do not include VINs, tokens, or personal
data.
