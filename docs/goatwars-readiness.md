# GoatWars hardware-free readiness

## Scope and verdict

Rebased onto GoatWars refactor `50fe6d6` plus the fixes on
`codex/goatwars-hardware-readiness`, against Store firmware
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
| Apps host suite | 128 tests, zero failures |
| Selected firmware suite | 1,408 tests, zero failures; two asset-regeneration tests excluded |
| Native badge-v1 execution | 20 seeded matches plus countdown, pause, settings, restart and render assertions pass |
| Exact VM compatibility | All imports and 53 instruction types in 17 game modules resolve against pinned VM sources/libraries |
| Actual released boot library | Real app pack loads dynamically; imported library exports and page lifecycle pass on native AtomVM with released boot.avm |
| Store packaging | 48,164 bytes, under 65,536-byte limit by 17,372 bytes; native pack and host pack tests pass |
| Store authentication | Disposable-key signed pack verifies; tampering is rejected; no production key or publishing used |
| Real firmware UI | Three integration scenarios pass: empty NVS launch/key routing, retained installation with offline reload failure, crashed game recovery to Home |
| Resource stress | Four AI profiles and 25 repeated entries pass at all three heap budgets; dense render succeeds at highest budget and reports expected OOM at lower budgets |
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
It uses 8-byte words; the ESP32 uses 4-byte words. Heap sweeps use 32,768,
65,536 and 131,072 words per process. These are stress boundaries, not measured
ESP32 capacity. The dense 3,588-cell fixture emits 3,629 display items and requires
the highest tested heap cap. Unexpected failures at any cap fail the runner.

Desktop timing does not prove the badge's 100 ms frame deadline. Physical display
queue drain, SPI/rotation/base-image configuration, internal RAM under Wi-Fi and
websocket load, keyboard feel/debounce, LEDs, power loss and electrical behavior
remain unmeasured. A signed pack verifies on host; native dynamic loading verifies
the delivered bytes and actual boot-library exports, not the ESP32 crypto NIF.
The UI persistence scenario uses simulated NVS and injected installed metadata;
it does not exercise an actual HTTPS transfer or physical flash wear/power loss.

## Artifact identity and first-device installation

Game pack SHA-256:
`e39d07cc8c4fbd7a439846cee0956f919318bd3c96064234f88fed6c567446d5`.
Released boot.avm is 524,880 bytes, SHA-256
`652d98edf174ea7ec650b9e573a4cb479fbf99fc7d017cddfdebe4fd97f2adbf`.
Release checksums verify and its seven partition rows match source exactly.

| Partition | Used bytes | Capacity | Headroom |
| --- | ---: | ---: | ---: |
| factory VM | 1,742,512 | 1,966,080 | 223,568 |
| boot | 524,880 | 557,056 | 32,176 |
| assets | 210,260 | 262,144 | 51,884 |
| main firmware | 660,956 | 671,744 | 10,788 |

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
This session's evidence is in `/private/tmp/goatwars-readiness`; temporary artifacts
should be regenerated if that directory is cleaned.

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
