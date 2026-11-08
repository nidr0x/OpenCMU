# Security policy

## Status

OpenCMU runs as root on the head unit and replaces files. Treat every payload
as privileged code. The project is alpha and has not been audited.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository, or contact the
maintainer listed there. Do not publish a working exploit before a fix is
available. Include:

- firmware version (`JCI_SW_VER`),
- payload version,
- tweak ids,
- a minimal reproduction against a fake root if possible.

## Threat model

| Asset | Concern |
| --- | --- |
| Head unit | A bad tweak or wrong firmware can break the UI or boot. |
| Backups | Losing `/data/opencmu/backups` removes the easy rollback path. |
| USB payload | Anyone who can write the USB can change what runs as root. |
| Vehicle data | VINs and logs can be personal data; do not publish them. |

OpenCMU does not defend against an attacker who already has root on the unit.
It does try to make accidental damage reversible.

## Design decisions

- Dry-run is the default; `--apply` is required for install and rollback.
- Firmware is checked against an explicit min/max range.
- Every modified file is backed up before the write.
- Writes are atomic, sync the temporary file, and refuse symlinks; backups and
  restores also refuse symlinked targets.
- Experimental tweaks are opt-in and ship no patch content.
- The `.up` builder is experimental and unsigned. The supported path is the USB
  payload with `bootstrap.sh`.
- The stock collector is a separate, opt-in payload. Its `.up` filename is a
  command injection evaluated by the factory updater, which is a real risk: it
  runs as root. It only reads from the unit and writes under
  `opencmu-dump/`, and the installer never uses this technique.

## Known limitations

- No code signing or signature verification of the payload.
- `SHA256SUMS` detects corruption, not tampering by someone who can rewrite it.
- No sandbox: tweaks are shell sourced as root.
- The updater's handling of `.up` files is undocumented and unverified.

## Secrets

Never commit credentials, tokens, VINs, or personal data. The installer does not
read or transmit them.

The collector copies stock firmware files, which are not redistributable. Keep
`opencmu-dump/` out of the repository.
