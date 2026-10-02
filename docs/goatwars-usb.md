# Install GoatWars over USB

This is an offline bench build: GoatWars modules are distributed between main and assets and the game is
listed on the home grid. It runs after reboot without Wi-Fi or a Store download.
The Store firmware is included; the game's public Store installation is separate.

## Run it yourself

Connect the badge over USB and close any serial monitor. In Terminal:

```sh
cd /Users/mike/code/_Learn/goatmire-2026/avm_badge_apps
./scripts/goatwars_install.sh
```

The installer uses the prepared `_build/goatwars-upstream-firmware` checkout:
[mwingert/avm_badge, feature/add-app-store-rebased](https://github.com/mwingert/avm_badge/tree/feature/add-app-store-rebased),
verified at `bf0cc9621b5fe9543a2c600ae43115e87fc78156`. No local firmware
patches are included. `AVM_BADGE_PATH` selects an explicit firmware checkout. It builds
firmware, assets and the current game, validates both partition limits, then auto-detects the board and flashes the two packs together. It resets
the board afterward. Run the same command again to repeat the installation.

The upstream checkout and dependencies are already prepared in this main directory.
For a fresh apps checkout, prepare them once before running the installer:

```sh
git clone --single-branch --branch feature/add-app-store-rebased \
  https://github.com/mwingert/avm_badge.git _build/goatwars-upstream-firmware
(cd _build/goatwars-upstream-firmware && mix deps.get)
```

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

The installer compiles current game sources inside the selected firmware project,
so the apps project’s sibling dependency does not select the USB build.

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
   then leads into M Square, 23×23 cells at 8 pixels per cell and a 200 ms steering interval.
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

On October 2, 2026, an earlier USB build was flashed and the user confirmed that
GoatWars displays and responds correctly. The current clean-upstream game worker was measured on the device: during play
the UI mailbox stayed at 0–7 messages, compared with more than 300 before.
The final normal USB build also passes the native VM checks. Human confirmation
of the new gameplay feel remains necessary. The bounded boot log showed Home,
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

Version 0.1.6 defaults to M Square, a 23×23 bitmap board. Game steps use one
asynchronous worker at a time so calculations do not block the upstream UI ticker.
The pen has a slightly lighter purple background without grid lines.
P1 uses a bright purple laser; the other player colors remain saturated. AI cruises straight
and checks longer side lanes when forced to turn; it still attempts nearby cutoffs.
Result screens use a smaller goat lower down, above the scores.
Rematches preserve board size, aspect and speed; leaving and reopening restores defaults.
The default is a 200 ms steering interval after each new game frame is prepared.
The worker previews the next step during that interval. With no human turn, the
preview is published at the deadline; late steering reuses the prepared AI and
recomputes movement. UI scheduling and display time still affect the actual rate.
A completed step reaches the render callback before the next step can replace it. The selected upstream firmware has a 100 ms UI ticker; settings below
100 ms cannot produce a frame per step. The app leaves firmware scheduler settings
unchanged. Human confirmation of movement and steering feel remains necessary.
Press T in the game for timing logs; M then restarts the same seed in legacy or
bitmap mode. The [performance guide](goatwars-performance.md) explains the local
benchmarks, physical checks and what the measurements cover.
