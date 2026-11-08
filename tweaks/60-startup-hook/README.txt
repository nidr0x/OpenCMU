Drop executable *.sh files here to run them once at boot.

OpenCMU starts each hook in the background from the stage script it patched,
after that stage finished its own work. A hook that hangs cannot delay the
boot; it only leaks one process until the unit restarts.

Hooks run as root. Keep them short and idempotent.
