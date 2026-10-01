# Install GoatWars over USB

This is an offline bench build: GoatWars modules are distributed between main and assets and the game is
listed on the home grid. It runs after reboot without Wi-Fi or a Store download.
The Store firmware is included; the game's public Store installation is separate.

## Run it yourself

Connect the badge over USB and close any serial monitor. In Terminal:

```sh
cd /Users/mike/code/_Learn/goatmire-2026/avm_badge_apps/.worktrees/goatwars-hardware/avm_badge_apps
./scripts/goatwars_install.sh
```

The installer uses the selected Store firmware worktree beside it. It builds and
checks firmware, builds assets and the current game, validates both partition
limits, then auto-detects the board and flashes the two packs together. It resets
the board afterward. Run the same command again to repeat the installation.

To prepare files without opening the board:

```sh
./scripts/goatwars_install.sh --build-only
```

It uses mise with Elixir 1.18.3 / OTP 27.1.2 when available, otherwise the `mix`
on PATH. Install esptool before the flashing run. The supported esptool names are
`esptool`, `esptool.py`, and `python3 -m esptool`. Do not pass `--port`.

Build products are in `_build/goatwars-usb/`. To use different checkouts or output:

```sh
AVM_BADGE_PATH=/absolute/path/to/Store-firmware \
GOATWARS_USB_OUTPUT=/absolute/path/to/output \
./scripts/goatwars_install.sh
```

The apps project's `../avm_badge` dependency must refer to that same firmware.
A different firmware checkout may require rebuilding dependencies first.

## What it writes

- `assets.avm` at `0x278000`: existing fonts, logo and animation plus game modules.
- `firmware.avm` at `0x2B8000`: Store firmware, game modules and the GoatWars home-grid entry.

NVS, the bootloader, partition table, VM, boot library and alternate firmware slot
are preserved. This board's base artifacts match pinned `badge-v1`; a full base
install is unnecessary. The script assumes the board boots the default main slot;
a board configured to boot the alternate slot must be handled separately.

Existing backups are in
`/Users/mike/code/_Learn/goatmire-2026/badge-backups/snapshots/`.
The script does not create another backup or erase flash. An interrupted two-pack
write can leave code and assets mismatched; rerun the installer after reconnecting.

GoatWars is bundled for this bench test rather than recorded as a Store app.
Running the ordinary assets flasher later replaces the game-containing archive;
rerun this installer to restore it. Firmware source files and the public Store
manifest are not changed by building these images.

## First physical test

1. Wait for Home. Press Right twice to reach home screen three, then press the
   square key for GoatWars. A three-second countdown should lead into a match.
2. Use Left/Right to take over player one. Space pauses and resumes. `S` opens
   player settings, arrows change selections, and Enter applies them.
3. Press `R` to rematch. Return Home using the normal navigation key, then reopen
   GoatWars and confirm the game starts fresh.
4. Restart the badge and reopen GoatWars without Wi-Fi; this USB build should
   still work. Let several matches finish and watch for freezes or blank frames.
5. Record any reboot, return to Home, missing text, sluggish input or visual
   corruption. Include what you pressed and how long it had been running.

Physical results are pending. We stopped before flashing or running device tests
at your request. Host/native readiness evidence is in
[the readiness report](goatwars-readiness.md). Store HTTPS remains a separate
known firmware risk; this offline test does not establish its reliability.

## Developer checks

When ready to resume verification, run `mix test` and
`python3 -m unittest discover -s test/scripts -v` in this worktree. The latter
uses fake tools and never accesses hardware. The full host suite, including the archive-edit regression, passed when
verification resumed on October 1. The badge now uses a simple obstacle-avoidance
controller; its settings offer Human, AI Simple and Inactive.

## Performance diagnostics

The new default uses a full-size bitmap board and a ticker with backpressure.
Press T in the game for timing logs; M then restarts the same seed in legacy or
bitmap mode. The [performance guide](goatwars-performance.md) explains the local
benchmarks, physical checks and what the measurements cover.
