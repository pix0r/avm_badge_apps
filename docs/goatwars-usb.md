# Install GoatWars over USB

This is an offline bench build: GoatWars modules are distributed between main and assets and the game is
listed on the home grid. It runs after reboot without Wi-Fi or a Store download.
The Store firmware is included; the game's public Store installation is separate.

## Run it yourself

Connect the badge over USB and close any serial monitor. In Terminal:

```sh
cd /Users/mike/code/_Learn/goatmire-2026/avm_badge_apps/.worktrees/goatwars-new-store/avm_badge_apps
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

The verified full-flash backup from this installation is in
`../recovery/badge-full-before.bin` (4 MiB, including private NVS data).
The script does not create another backup or erase flash. An interrupted two-pack
write can leave code and assets mismatched; rerun the installer after reconnecting.

GoatWars is bundled for this bench test rather than recorded as a Store app.
Running the ordinary assets flasher later replaces the game-containing archive;
rerun this installer to restore it. Firmware source files and the public Store
manifest are not changed by building these images.

## First physical test

1. Wait for Home. Press Right twice to reach home screen three, then press the
   clover key for GoatWars. The title waits for Enter. A three-second countdown
   then leads into M Square, 23×23 cells at 8 pixels per cell.
2. Use Left/Right to take over player one. Space pauses and resumes. `S` opens
   player settings, arrows change selections, and Enter applies them. G cycles
   S/M/L/XL boards; A switches Square/Wide; F slows down by 10 ms and V speeds up by 10 ms,
   from 50–400 ms per step. Enter applies the choices.
   The default key pairs are Left/Right, Z/X, 1/2 and 9/0 for players 1–4.
3. Press `R` to rematch. Return Home using the normal navigation key, then reopen
   GoatWars and confirm the game starts fresh.
4. Restart the badge and reopen GoatWars without Wi-Fi; this USB build should
   still work. Let several matches finish and watch for freezes or blank frames.
5. Record any reboot, return to Home, missing text, sluggish input or visual
   corruption. Include what you pressed and how long it had been running.

On October 2, 2026, this build was flashed over USB and the user confirmed that
GoatWars displays and responds correctly. The bounded boot log showed Home,
Wi-Fi reconnection and clock synchronization. Store opens; its online catalog
was not verified because the network was poor.
Host/native checks passed, including actual Store-pack and split USB-image
loading on the pinned badge-v1 VM and boot library. These checks do not establish
the reliability of HTTPS catalog or pack downloads on the physical badge.

## Developer checks

When ready to resume verification, run `mix test` and
`python3 -m unittest discover -s test/scripts -v` in this worktree. The latter
uses fake tools and never accesses hardware. The full host suite, including the archive-edit regression, passed when
verification resumed. The badge uses bounded escape and route-interception
checks; its settings offer Human, AI Simple and Inactive.

## Performance diagnostics

Version 0.1.6 defaults to M Square, a 23×23 bitmap board and a ticker with backpressure.
The pen has a slightly lighter purple background without grid lines.
P1 uses a bright purple laser; the other player colors remain saturated. AI cruises straight
and checks longer side lanes when forced to turn; it still attempts nearby cutoffs.
Result screens use a smaller goat lower down, above the scores.
Rematches preserve board size, aspect and speed; leaving and reopening restores defaults.
The installer also includes firmware with a page-specific tick cadence; this is
required for fine timing and sub-100 ms play. It requests up to 20 frames/s at
50 ms, subject to actual VM/display throughput. No physical frame-rate claim
has been verified for this build.
Press T in the game for timing logs; M then restarts the same seed in legacy or
bitmap mode. The [performance guide](goatwars-performance.md) explains the local
benchmarks, physical checks and what the measurements cover.
