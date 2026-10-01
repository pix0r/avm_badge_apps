# GoatWars hardware-free readiness

Current title, countdown and badge-AI evidence is recorded below. Earlier
optimization measurements are in [performance verification](goatwars-performance.md).
The remaining sections record earlier readiness stages.

## October 1 title, countdown and opponent update

Apps branch `beamwars` keeps the detailed goat/lightcycle title and crash tagline.
Enter starts a separate full-board countdown with four cannon launchers; riders
and scores stay frozen through 3/2/1. Pause, win and draw retain goat artwork.
The badge AI now checks three moves with bounded escape/lookahead, pursues nearby
opponents, lays trails across projected routes and varies comparable safe choices.
An evolving seed reproduces a match; the one fixed-point seed is normalized.

TDD covered the board countdown and collision avoidance, interception, seed
variation/evolution, bitmap parity and constant work with dense trail maps.
All 184 apps tests, five real firmware UI integration scenarios and 11 Python
checks pass. Native badge-v1 execution resolves all imports and 63 instructions
in 21 game modules. Real Store and rebuilt split USB packs load and play on the
released boot library. Heap fixtures, 900 seeded rounds and 32 retained frames
pass the existing caps. The score/energy checkpoint uses controlled state rather
than the previous AI's exact route.

The app pack is 64,944 bytes, with 592 bytes below the Store limit. The offline
USB main is 667,300/671,744 bytes; assets are 262,144/262,144 bytes. This update
adds 1,972 bytes over the restored-art pack. Native desktop AtomVM measured about
0.64–0.67 ms per four-rider frame at both 24×14 and 78×46. Host work is capped at 2,500
reductions across all three board sizes, with no board-wide AI search. These are
desktop checks; hardware frame timing and gameplay feel remain unmeasured.
The paired `avm_badge` source and branch were unchanged, and no hardware was flashed.

## Scope and verdict

Rebased onto GoatWars refactor `50fe6d6` plus the fixes on
`codex/beamwars-hardware-readiness`, against Store firmware
`ff532649da2acb213680f2e578f541a21380aaef` (`origin/feature/add-app-store`).
The original development checkouts were not modified. The readiness scripts,
fixtures and integration gates now use the refactored GoatWars namespace and layout.

The game passes the available hardware-free gates. This establishes substantially
more confidence than host tests alone, but does not establish reliable first-run
operation on physical hardware. In particular, the selected firmware documents
an ESP32 SSL crash risk in Store HTTPS downloads. That delivery path remains a
known unresolved hardware risk.

## Acceptance evidence

| Gate | Result |
| --- | --- |
| Apps host suite | 159 tests, zero failures; 11 Python checks pass |
| Selected firmware suite | 1,408 tests, zero failures; two asset-regeneration tests excluded |
| Native badge-v1 execution | 20 seeded matches plus countdown, pause, settings, restart and render assertions pass |
| Exact VM compatibility | All imports and 59 instruction types in 19 game modules resolve against pinned VM sources/libraries |
| Actual released boot library | Real app pack loads dynamically; imported library exports and page lifecycle pass on native AtomVM with released boot.avm |
| Store packaging | 54,504 bytes, under the 65,536-byte limit; native pack and host pack tests pass |
| Store authentication | Disposable-key signed pack verifies; tampering is rejected; no production key or publishing used |
| Real firmware UI | Five integration scenarios pass, including 50/110/130/400 ms cadence, time counters, ticker backpressure, offline launch/reload and crash recovery |
| Resource stress | All three board sizes, exact tick-97 state, dense board, 25 entries and 900 total rounds pass at 4,096/8,192/16,384 words; 32 retained frames in each size pass at 32,768 words; binary memory is checked separately |
| Actual USB game delivery | Rebuilt main/assets packs load together on native AtomVM; default middle round ends at tick 90, small at 91 and full-size at 207 |
| Simulator | Built-in splash/home/reboot check passes; game interaction covered separately through real UI |
| First installation commands | Fake-flasher tests cover base image offsets/checksum refusal, modern/legacy/Python esptool discovery and error propagation |
| Partition capacity | Released VM/boot plus built assets/main fit all source and released binary partitions |

The whole-project `mix atomvm.check` passes after Store packaging creates empty
host-only dependency directories. ExAtomVM still has a fresh-check target traversal
bug involving absent Phoenix build directories; this was not repaired. The strict
game audit and actual released-library execution provide independent evidence.

## Fixes proven by failing tests first

- Badge play no longer retains an ever-growing replay history; headless replay
  recording remains available, including deterministic regression fixtures.
- Runtime map access avoids an unavailable compiler fallback and reduces the
  original 86,392-byte pack below the Store limit.
- AI exploration stops when further search cannot change its score or safety
  decision. Eight pre-change replay digests remain identical. Native Pro fixture
  timing fell from approximately 71.5 seconds to 8.7 seconds for 222 ticks.
- Firmware flashing supports installed esptool names and propagates command
  failures. The complete Mix build/check/metadata/flash path was exercised with
  a fake flasher; no serial port was accessed.

## Resource and hardware interpretation

Native runtime is the exact `badge-v1` source
`a08e9fc1e20131e0d2b1432691ea198020bce0ff`, built in Release mode on macOS ARM64.
It uses 8-byte words; the ESP32 uses 4-byte words. Current heap sweeps use 4,096,
8,192 and 16,384 words per process; retained-frame tests use 32,768 words.
These are stress boundaries, not measured ESP32 capacity. Current dense bitmap
rendering emits 26 items; the earlier map-rendering fixture emitted 3,629.
Unexpected failures at any cap fail the runner.

Desktop timing does not prove the badge's 100 ms frame deadline. Physical display
queue drain, SPI/rotation/base-image configuration, internal RAM under Wi-Fi and
websocket load, keyboard feel/debounce, LEDs, power loss and electrical behavior
remain unmeasured. A signed pack verifies on host; native dynamic loading verifies
the delivered bytes and actual boot-library exports, not the ESP32 crypto NIF.
The UI persistence scenario uses simulated NVS and injected installed metadata;
it does not exercise an actual HTTPS transfer or physical flash wear/power loss.

## Artifact identity and first-device installation

Game pack SHA-256:
`4e1f785862298cac10ba3cc346dcb730b6873c01661d42d05feabfbf8f482d11`.
Released boot.avm is 524,880 bytes, SHA-256
`652d98edf174ea7ec650b9e573a4cb479fbf99fc7d017cddfdebe4fd97f2adbf`.
Release checksums verify and its seven partition rows match source exactly.

| Partition | Used bytes | Capacity | Headroom |
| --- | ---: | ---: | ---: |
| factory VM | 1,742,512 | 1,966,080 | 223,568 |
| boot | 524,880 | 557,056 | 32,176 |
| USB assets with game modules | 260,440 | 262,144 | 1,704 |
| USB main firmware | 666,172 | 671,744 | 5,572 |

A blank device needs the pinned base image (including boot.avm and matching
partition table), assets, and this Store firmware before installing the app.
Use the repository's documented base/assets/firmware commands; never pass a port
or assume flashing main installs the base or assets. The public HTTPS Store path
is not cleared for reliable first-device use by this validation. A provisioned
HTTP bench Store is a documented alternative, but has not been board-tested here.

## Repeatable checks

Run `mix test` in the apps worktree. In the selected firmware worktree run
`mix test`, `mix sim.check`, and the integration script with
`MIX_TARGET=host MIX_ENV=test mix run --no-start
../avm_badge_apps/scripts/goatwars_integration_test.exs` (join the command lines).
Build/sign locally with a disposable key using the existing Store pack task;
do not publish its test manifest.

For native execution, build AtomVM and atomvmlib from the pinned source, then run
`scripts/goatwars_native.sh` with Elixir 1.18.3 / OTP 27.1.2 on PATH and:

- `ATOMVM_SOURCE`: pinned AtomVM checkout
- `ATOMVM_BUILD`: its Release build directory
- `ATOMVM_BOOT_PACK`: checksum-verified released boot.avm
- `AVM_BADGE_PATH`: selected Store firmware checkout
- `GOATWARS_RESULTS`: directory for packs and logs

The runner checks source and boot identities, audits compiled code, loads the
actual app pack and runs lifecycle/match/resource checks. It fails on unexpected
errors. Generated VM builds, packs, disposable keys and logs stay outside the repo.
Earlier evidence is in `/private/tmp/goatwars-readiness`; current performance and
USB evidence is under `/private/tmp/beamwars-readiness/goatwars-coarse-verified-*`
and `/private/tmp/beamwars-readiness/goatwars-middle-native`.
Temporary artifacts should be regenerated if those directories are cleaned.

## Physical acceptance still required

On the first available device: install from blank flash; verify boot and assets,
install the exact signed game, launch offline, type through settings and a match,
rematch and leave/reenter, reboot and reload, and provoke a failed download.
Measure frame time and internal RAM with radio services active; soak dense play.
Confirm failed app execution returns Home. Exercise interrupted writes and supply
changes only with recovery firmware/cable available. Resolve the Store SSL crash
before treating public HTTPS installation as dependable.

## USB bench build

The worktrees now live in the persistent, ignored directory
`avm_badge_apps/.worktrees/goatwars-hardware/`, with apps and selected firmware
next to each other. [The USB installer](goatwars-usb.md) packages GoatWars with
the assets and adds its page to the grid for offline testing. A complete flash
backup was read; this board matches the released VM, boot library, bootloader
and partition table. No test firmware was flashed and physical results remain
pending. Tests added for the installer passed before device testing was stopped;
the final archive-edit regression suite rerun is deferred.

## October 1 performance correction

The first physical run exhibited severe, irregular lag. Badge opponents now use
`SimpleBot`, including settings, B and rematches. A second fix removes complete
trail-map scans from ordinary ticks and makes explosion clearing local. Advanced
search remains available only to headless Match experiments. The updated host
suite passes 138 tests; three firmware UI cases and six installer tests pass.
The formerly deferred archive-edit regression now passes in the full suite.
See [resource measurements](goatwars-resources.md) for the controlled native
comparison. The new physical test remains pending; the script was rebuilt in
build-only mode and no device was reflashed by this chat.

## October 1 bitmap optimization

The full-board bitmap build meets the local 10× CPU target, including the pinned
C rasterizer. State at the reported tick97 point and repeated rounds pass on
native AtomVM. The ticker uses backpressure. The installer now distributes game
modules between main and assets while preserving every existing asset.
All work remains in the isolated paired worktrees; the badge was untouched.
See [performance verification](goatwars-performance.md) for commands, limits and
T/M device timing controls.

## October 1 smaller-board follow-up

Further loop and text-rendering optimization measures another 1.79× combined
native CPU gain against `50696f1`, below the requested 5×. The authorized fallback
defaults to 24×14 cells, drawn at 13 pixels each. Its bitmap and retained-frame
binary samples are over 10× smaller. Settings G toggles the original 78×46 board;
both modes retain 100 ms steps and pass the final native memory/USB gates.
All final checks and image rebuilding were hardware-free. The new physical
speedup remains unmeasured.

## Middle board and speed settings

Version 0.1.2 defaults to 51×30 with 6-pixel cells; G cycles all three board
sizes and F cycles 100/200/300/400 ms steps. Applied choices survive rematches;
canceling settings preserves custom rules. Adjacent controls are Left/Right,
Z/X, 1/2 and 9/0. Native lifecycle tests exercise speed and key routing, and the
actual USB split is rebuilt and tested. The new middle board passes 300 seeded
rounds across three heap caps, with a peak sampled binary usage of 8,500 bytes
at frame boundaries and 202,684 bytes with 32 rendered frames retained. Total
stress is 900 rounds across the three sizes. The badge was not accessed.

## Fine speed and faster tick requests

Version 0.1.3 changes speed in 10 ms increments from 50–400 ms. F increases the
step duration and V decreases it. Firmware now honors a page's optional tick
interval, preserving the 100 ms default for existing pages. The timer still
waits for each callback to finish before sending another tick. UI sleep/status
accounting uses 10 ms units; frame throttling uses the next requested interval.
Small callback jitter no longer shifts each game deadline; long stalls advance
once without a catch-up loop. The new firmware passes the full 1,408-test suite
and game integration gates. Physical sub-100 ms throughput remains unmeasured.
