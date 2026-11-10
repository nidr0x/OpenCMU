# Writing a tweak

A tweak is a directory under `tweaks/` with three files:

```text
tweaks/30-my-tweak/
├── tweak.env
├── apply.sh
└── rollback.sh
```

The installer sources `apply.sh` in a subshell with `set -eu`. A non-zero exit
aborts the install. `rollback.sh` is sourced the same way, in reverse order.

## tweak.env

```sh
TWEAK_NAME="Short name"
TWEAK_RISK="low"
TWEAK_DESCRIPTION="What it changes and why."
# TWEAK_EXPERIMENTAL=1
```

## Environment available to scripts

| Variable | Meaning |
| --- | --- |
| `OPENCMU_ROOT` | Target root, `/` on the unit or a fake root in tests. |
| `OPENCMU_USB` | Payload directory. |
| `OPENCMU_STATE` | State directory under the target root. |
| `OPENCMU_BACKUP` | Backup directory for this run. |
| `OPENCMU_DRY_RUN` | `1` during a dry run. |
| `OPENCMU_ENABLE_EXPERIMENTAL` | `1` when `--experimental` was passed. |
| `dir` | This tweak's directory. |
| `ver` | Detected `JCI_SW_VER`, or `unknown`. |

`lib/common.sh` is already loaded. Use its helpers instead of reimplementing
them.

## Helpers

| Helper | Purpose |
| --- | --- |
| `backup_file PATH` | Copy `PATH` into the run backup; prints the backup path. |
| `restore_file PATH` | Restore `PATH` from the run backup. |
| `record_created PATH` | Remember that `PATH` did not exist before this run. |
| `rollback_path PATH` | Restore from backup, or remove a created file. |
| `atomic_write DEST SRC` | Replace `DEST` via a same-directory temp file. |
| `install_replacement TARGET REPL [SHA256]` | Backup, verify, replace. |
| `sha256_file PATH` | Print a SHA-256 digest. |
| `log`, `warn`, `die` | Consistent output. |

## Patch helpers

`lib/patch.sh` is loaded alongside `common.sh`. It contains the anchored
editors used by the firmware tweaks. All of them refuse a missing or symlinked
target, take the first backup of the file, write atomically, and abort before
writing when an anchor does not match exactly once.

| Helper | Purpose |
| --- | --- |
| `patch_subst FILE OLD NEW` | Replace one literal on one line. |
| `patch_subst_all FILE OLD NEW [MIN]` | Replace every occurrence, requiring at least `MIN` (default 1). |
| `patch_number FILE KEY OLD NEW` | Rewrite the numeric token `OLD` on the single line containing `KEY`. |
| `patch_quoted_value FILE KEY VALUE` | Replace the quoted value that follows `KEY`. |
| `patch_key_value FILE KEY VALUE` | Rewrite the value after `KEY =` without assuming the stock value. |
| `append_once FILE MARKER BLOCK` | Append `BLOCK` unless `MARKER` is already present. |
| `prepend_once FILE MARKER BLOCK` | Put `BLOCK` at the top of the file, for configs where the first value wins. |
| `patch_line_after_once FILE ANCHOR OLD NEW [MARKER]` | Replace `OLD` on the first line after `ANCHOR`; `NEW` may span lines when `MARKER` is given. |
| `insert_before_once FILE MARKER ANCHOR BLOCK` | Insert `BLOCK` before the single line containing `ANCHOR`. |
| `insert_after_once FILE MARKER ANCHOR BLOCK` | Insert `BLOCK` after the single line containing `ANCHOR`. |
| `sm_disable_services FILE SERVICE...` | Set `autorun="no"` in the matching `<service>` blocks of a Service Manager config. |
| `sm_set_attribute FILE ATTR VALUE SERVICE...` | Set one attribute on the matching `<service>` opening tags, adding it when absent. |
| `sm_set_affinity FILE MASK SERVICE...` | Set `affinity_mask` on the matching `<service>` entries. |
| `sm_add_child FILE SERVICE LINE` | Insert one line before the named service's `</service>`, once. |

Two rules matter when you use them:

- **Anchors are exact.** If the stock file does not contain the literal, the
  tweak fails instead of guessing. That is the point: a firmware layout that
  does not match the one the tweak was written for is not a layout to patch.
- **Backups are first-wins.** A tweak that edits the same file twice rolls back
  to the pre-install content, not to an intermediate state.

`append_once`, `prepend_once`, `insert_before_once` and `insert_after_once`
take a block file shipped inside the tweak directory, so the marker stays in the
target and rollback can be verified. `prepend_once` exists for `sshd_config`,
where the first value of a keyword wins; appending a second `PasswordAuthentication`
line would not override the stock one.

`sm_disable_services` writes a Service Manager config only once, after at least
one requested service was located. A name this firmware does not define is
reported on stderr and skipped, because service sets differ between regions; if
none of the names exist the tweak aborts with the file untouched. That is why
the `disable-*` tweaks cannot leave a half-edited `sm.conf` behind.

`sm_set_affinity` follows the same rule for `affinity_mask`: it rewrites the
attribute when the service already has one and adds it to the opening tag when
it does not, then writes the file once. Services it cannot pin abort the tweak.
`patch_key_value` exists for files whose stock value differs between builds: it
anchors on the key and replaces whatever value follows the `=`, so the tweak
never hardcodes a number it has not verified.

`sm_add_child` covers the other Service Manager change: a child element of a
named service, such as `environ_var`. It has no stable anchor of its own, so the
helper inserts before that service's `</service>` and skips the insert when the
exact line is already there.

## Tweaks that need an input

Some changes cannot be written blind. Those tweaks take their missing fact from
the environment and abort when it is absent:

- `57-firewall-iptables-restore` takes `OPENCMU_WCP_RULES` and
  `OPENCMU_FW_ANCHOR`. The anchor is the line that opens the firewall function
  in the stock `jci-fw.sh`; guessing it would mean guessing where a `return`
  lands at boot. On stock 74.00.324 the verified anchor is `wcpset()`: the
  firmware ships no `firewall_start()`, and the WCP chain is built inline by
  `do_start()` and `wcpset()`. A ruleset in iptables-save format can be
  transcribed from the `$IPTABLES` lines of those two functions.
- `58-install-aatouch` takes `OPENCMU_AATOUCH_SHIM` and
  `OPENCMU_AATOUCH_SHA256`. The shim is AGPL-3.0 third-party code, so the repo
  ships no copy and the digest pins exactly the file the user supplied.
- `59-enable-aa-touch` takes no input, but refuses unless the shim is already on
  the unit at `/data_persist/oem-aa-mod/libpatch-blmjciaapa.so`.
- `61-keep-cluster-compass`, `62-disable-touchscreen`,
  `76-enable-wifi-client` and `77-boot-profiler` take no generated asset, but
  refuse unless `/data/opencmu/boot.d` exists, which means
  `60-startup-hook` already ran.
- `75-enable-ssh` takes `OPENCMU_SSH_PUBKEY`, one RSA public key in OpenSSH
  format. It refuses ed25519 because the unit ships OpenSSH 5.9, and it does
  not change firewall rules.
- `38-order-audio-sources` takes `OPENCMU_AUDIO_ORDER`, a comma-separated list
  of stock source IDs. It appends a guarded wrapper to `systemApp.js` that
  reorders the entertainment source list and leaves the entry selection
  untouched; each listed ID must match a stock ID and IDs cannot repeat. Stock
  74.00.324 IDs: `TrafficInfo`, `FMRadio`, `AMRadio`, `DAB`, `SatRadio`,
  `XmAudio`, `AhaRadio`, `Pandora`, `Stitcher`, `BTAudio`, `CarPlayWifi`,
  `CarPlay`, `AndroidAuto`, `USB_A`, `USB_B`, `CD`, `AuxIn`, `DVD` and `TV`.
  `TrafficInfo` is the traffic-alert item, not an audio source, but it lives in
  the same list.
- `76-enable-wifi-client` takes `OPENCMU_WIFI_SSID` and `OPENCMU_WIFI_PSK`.
  The optional `OPENCMU_WIFI_STATIC_IP`, `OPENCMU_WIFI_NETMASK` and
  `OPENCMU_WIFI_GATEWAY` replace DHCP.

## Boot-time runtimes

A tweak that has to keep running belongs in `/data/opencmu/boot.d`, which
`60-startup-hook` starts in the background at boot. `61-keep-cluster-compass`,
`62-disable-touchscreen`, `76-enable-wifi-client` and `77-boot-profiler` are
the examples: `apply.sh` installs one executable script there and starts
nothing itself, so the installer still works against a mounted image. Each
script owns its own lock and log; `62` has `--release`, `76` has `--stop`, and
`77` is a one-shot that exits by itself.

## Rules

1. **Always provide a rollback.** If the change cannot be undone from the run
   backup, do not ship it. It must be a safe no-op when `apply.sh` never ran:
   ids are journaled before applying, so rollback can be called after a crash.
2. **Never touch the bootloader, kernel, or recovery partitions.**
3. **Never write through a symlink.** `atomic_write` rejects it.
4. **Fail closed.** Missing files, unexpected hashes, or an unknown firmware
   should abort, not guess.
5. **No network access, no telemetry, and no background process from
   `apply.sh`.** A runtime that must keep running is installed into
   `/data/opencmu/boot.d` (see above) and started by the boot hook, never
   spawned by the installer.
6. **Do not modify `JCI_SW_VER`.**
7. **Keep it idempotent where possible.** Re-applying should not corrupt state.
8. **Respect `OPENCMU_DRY_RUN`.** The installer skips `apply.sh` in dry runs;
   do not work around that.
9. **Use a safe id.** Tweak directory names must match `[A-Za-z0-9._-]+` and
   must not be `.` or `..`; the installer rejects anything else.

## Experimental templates

`tweaks/90-replacement-template/` and `tweaks/91-touch-replacement/` are
templates, not patches. They replace a file only when the user provides:

```sh
# tweaks/90-replacement-template/tweak.local.env (gitignored)
TARGET_FILE=/path/on/the/unit
REPLACEMENT_FILE=/path/on/the/usb/patched-file
EXPECTED_SHA256=<sha256 of the stock TARGET_FILE>
```

Use them for a file that has no bundled tweak yet. `91-touch-replacement` is a
template only: the bundled `43-touch-while-driving` and `62-disable-touchscreen`
implement the two supported touch behaviours through small, reversible patches
and runtimes.

`EXPECTED_SHA256` is strongly recommended. Without it, the tweak will replace a
file it cannot identify, which is how units get bricked. The templates refuse to
run without `--experimental`.

## Example: 00-example

`tweaks/00-example/apply.sh` writes `/data/opencmu/example-marker.txt`, records
whether the file already existed, and backs it up. `rollback.sh` calls
`rollback_path`, which restores the backup or removes the file. It is the
smallest complete tweak and the one used by `tests/smoke.sh`.
