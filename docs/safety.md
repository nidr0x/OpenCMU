# Safety

**OpenCMU is alpha software. Bench testing only.** The installer has been
tested against a fake root, not against a real CMU. Nothing here proves that a
tweak behaves correctly on your firmware, region, or hardware revision.

## Preflight checklist

- [ ] The unit is on a bench supply or a car you can leave parked.
- [ ] `JCI_SW_VER` in `/jci/version.ini` is inside the manifest range.
- [ ] You have a known-good stock recovery USB for this exact firmware.
- [ ] You have read `docs/recovery.md`.
- [ ] The USB is FAT32, MBR, and the payload passes `SHA256SUMS`.
- [ ] You have a copy of the payload on another machine.
- [ ] You are not relying on this unit as your only transport.

## Power and media

- Keep the ignition on and the USB connected until the unit is idle again.
- Do not unplug the USB during an install.
- Do not use a USB hub, an SD adapter, or a drive with a activity LED you cannot
  see.
- Use a small, known-brand USB drive. Cheap drives drop out under load.

## Risk levels

| Risk | Meaning |
| --- | --- |
| `low` | Writes only under `/data/opencmu`. Cannot affect the UI. |
| `medium` | Changes a user-space config file with a tested rollback. |
| `high` | Replaces a system file. Wrong file or wrong firmware can break the UI. |

Experimental tweaks (`TWEAK_EXPERIMENTAL=1`) are skipped unless `--experimental`
is passed, and they still require a per-tweak `tweak.local.env`. They ship no
patch of their own.

## What OpenCMU never does

- It does not write to the bootloader, kernel, or recovery partitions.
- It does not modify `JCI_SW_VER` or the firmware version file.
- It does not implement VIN checks, license checks, or phone-home behavior.
- It does not keep a network service running.
- It does not disable the car's safety warnings automatically.

If a proposed tweak needs any of the first two, it does not belong here.

## First run on a bench unit

1. Run the installer without `--apply` and read the plan.
2. Apply only `00-example`.
3. Confirm the marker and the receipt exist.
4. Roll back and confirm the marker is gone.
5. Only then try one real tweak at a time.

## If something looks wrong

Stop. Do not apply more tweaks. Run the rollback path in `docs/recovery.md`,
then re-check the unit on the bench before driving.
