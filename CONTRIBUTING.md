# Contributing

## Clean-room policy

OpenCMU is an independent project. Contributions must be your original work or
code you can license under MIT.

Do not contribute:

- code, binaries, or scripts extracted from Miatafy, ScreenTune, MZD AIO, or any
  other proprietary package;
- themes, images, fonts, sounds, or text copied from those packages;
- patches that only work by reproducing someone else's licensed payload;
- anything that bypasses a license, VIN, or payment check.

If you reverse-engineer a file format or a protocol, describe the format in your
own words and write your own implementation.

## Development

```sh
make test    # smoke test against a fake root
make dist    # build the USB payload and the experimental .up
```

Requirements: POSIX `sh`, `awk`, `cp`, `mv`, `sha256sum` or `shasum`, and
Python 3 for the `.up` builder.

## Style

- Shell: POSIX `sh`, no bashisms, quote expansions, `set -eu` in executables.
- Keep functions small and name them after what they do.
- Use `die` for fatal errors and `warn` for recoverable ones.
- Never write through a symlink; use `atomic_write`.
- New tweaks need `tweak.env`, `apply.sh`, and `rollback.sh`.
- Document new manifest or tweak keys in `docs/`.

## Tests

`tests/smoke.sh` must pass. Add a case when you add a tweak or change the
installer's behavior. Tests use a temporary fake root and must not touch a real
CMU or the repository's tracked files.

## Commits and pull requests

- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- Keep the pull request body to what changed and how it was verified.
- State explicitly whether the change was tested on a real unit. "Fake root
  only" is an acceptable and useful answer.
