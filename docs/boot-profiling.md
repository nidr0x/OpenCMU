# Profiling boot time

`77-boot-profiler` is a read-only runtime that records when a real boot reaches
its readiness milestones. Use it to find where boot spends time before choosing
disable or retiming tweaks, and to measure whether a tweak actually helped.

It starts nothing, stops nothing, and edits nothing: it polls a short list of
artifacts once per second, writes one line per milestone, and stops.

## Evidence behind each milestone

| Milestone | Probe | Stock evidence (74.00.324) |
| --- | --- | --- |
| `HMI_UP` | process `jciMMUI` running | service name in `jci/sm/sm.conf` |
| `WIFI_MODULES` | `/sys/class/net/wlan0` exists | modules loaded by `start_wifi.sh` |
| `HOSTAPD_UP` | process `hostapd` running | real binary `/usr/sbin/hostapd` |
| `WIFI_READY` | `/var/run/start_wifi_ready` exists | `start_wifi.sh:65` touches it |
| `CARPLAY_UP` | `netstat` ESTABLISHED line with host `192.168.53.` or `192.168.100.` and port `:7000` or `:7100` | subnets: `jci-wifiap.sh` (AP) and `jci-fw.sh` (WCP); port 7000 accepted on wlan0 by the stock firewall (`jci-fw.sh:88`). Port 7100 is community-reported and was not found in stock; the probe matches either. |

Two limits worth knowing before reading numbers:

- Timestamps are whole seconds of `/proc/uptime`. Differences under ~1 s are
  noise; run each configuration at least twice.
- `CARPLAY_UP` detects wireless sessions only. A USB CarPlay session does not
  create a TCP line.

## Install

The profiler is started by the boot hook, so `60-startup-hook` and
`77-boot-profiler` must be applied in the same run:

```sh
sh install.sh --apply --experimental --tweaks "60-startup-hook 77-boot-profiler"
```

Then reboot the unit. On the next boot the hook starts the profiler right after
`stage_gap2`, so `BOOT` marks the earliest point OpenCMU can observe. Processes
that start before it are invisible to the timeline; compare milestone deltas,
not absolute boot time.

## Collect the log

The log is `/data/opencmu/logs/boot-profiler.log` (one block per boot, oldest
first, capped at 128 KB):

```sh
ssh root@192.168.53.1 cat /data/opencmu/logs/boot-profiler.log
```

SSH access needs `75-enable-ssh` (key-only, see `docs/tweaks.md`). Without SSH,
apply the tweaks, do the reboots, then read the file from the unit over the
network any way the unit already allows — the profiler never writes to the USB
drive.

## Reading the log

```text
8.3 BOOT
8.4 EVENT WIFI_MODULES elapsed=0.1
9.9 EVENT HMI_UP elapsed=1.6
15.2 EVENT HOSTAPD_UP elapsed=6.9
16.0 EVENT WIFI_READY elapsed=7.7
60.1 STEADY
60.1 SNAPSHOT WIFI_UP
60.1 SNAPSHOT TCP_ESTABLISHED
60.1 DONE
```

- `BOOT` — the hook started. Uptime on the left, elapsed since `BOOT` on the
  right.
- `EVENT` — the moment a milestone was first observed to be true.
- `SKIP` — a tool was missing, so that milestone was not probed.
- `STEADY` / `SNAPSHOT` — state at the end of the window; `SNAPSHOT` lines show
  what was still true, which catches regressions an `EVENT` run can miss.
- `DONE` — the window closed. A missing `EVENT` means the milestone did not
  happen within the window (default 120 s).

## A/B method

1. Baseline: install the profiler alone, reboot twice, note both runs.
2. Candidate: apply the profiler **and** the candidate tweaks in the same run,
   reboot twice, note both runs.
3. Compare `EVENT elapsed=` values per milestone.
4. Roll back and confirm the baseline numbers come back.

```sh
sh install.sh --usb /media/USB --root / --apply --rollback
```

## Milestones and candidate tweaks

| Observation | Candidates |
| --- | --- |
| `WIFI_MODULES` or `WIFI_READY` late, or a long gap between them | `54-earlier-wifi-init` |
| Everything stalls while the AP or Wi-Fi work spins up | `54-wifi-boot-off-busy-core` |
| `HMI_UP` late | the `64-*`–`73-*` service disables, checked against `sm.conf` |
| Off-board connectivity work before the UI is ready | `56-disable-offboard` |
| `CARPLAY_UP` late | `55-carplay-engine-off-busy-core` |

Each candidate is reversible; roll back between measurements so the unit always
ends in a known state.

## Overrides

Every input has an environment override, so the same script also runs on a
mounted image or a fake root:

| Variable | Default | Meaning |
| --- | --- | --- |
| `OPENCMU_PROFILER_LOG` | `/data/opencmu/logs/boot-profiler.log` | log path |
| `OPENCMU_PROFILER_UPTIME` | `/proc/uptime` | uptime source |
| `OPENCMU_PROFILER_WLAN` | `/sys/class/net/wlan0` | module milestone probe |
| `OPENCMU_PROFILER_READY_FLAG` | `/var/run/start_wifi_ready` | readiness flag |
| `OPENCMU_PROFILER_HMI_PROC` | `jciMMUI` | HMI process name |
| `OPENCMU_PROFILER_CARPLAY_HOSTS` | `192.168.53. 192.168.100.` | host prefixes |
| `OPENCMU_PROFILER_CARPLAY_PORTS` | `:7000 :7100` | port substrings |
| `OPENCMU_PROFILER_WINDOW` | `120` | polling window, seconds |
| `OPENCMU_PROFILER_STEADY` | `45` | settle time before the snapshot |
| `OPENCMU_PROFILER_LOCK` | `/tmp/opencmu-boot-profiler.lock` | single-run lock |

Only one run may be active at a time; a second run exits immediately and logs
the pid of the active one.
