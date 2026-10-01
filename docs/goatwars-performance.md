# GoatWars performance verification

The October 1 build keeps the 78×46 board and its movement, scoring,
explosion and contraction rules. Badge occupancy is a fixed 14,352-byte RGBA
bitmap; paths are packed coordinate binaries. Rendering submits one scaled
board image. The board background is solid; the former grid lines are omitted.
Headless matches still use maps. The firmware ticker waits for a completed UI
callback before requesting another frame, preventing a backlog ahead of keys.

## Recorded baseline and results

Baseline is `a1e6f4b`, the SimpleBot build Mike reported was still too slow.
Both versions use the same benchmark, badge-v1 VM
`a08e9fc1e20131e0d2b1432691ea198020bce0ff`, released boot library and native
ARM64 Release interpreter, with JIT off and eight-byte words. Five deterministic
rounds complete 1,035 ticks in each version. The pinned AtomGL driver
`11be5f9a85a6eabb3ffcd331ed8678101224b237` rasterizes all 207 frames of one
round, 30 times per frame, at 320×240 with the built-in font.

| Work | Before | After | Improvement |
| --- | ---: | ---: | ---: |
| Five complete rounds: advance + render | 10.014 s | 0.373 s | 26.83× |
| Whole-round advance + render + C raster CPU | — | — | 17.88× |
| Retained state, late round | 4,301 words | about 483 words | about 89% less live heap |
| Peak state across 100 rounds | 4,581 words in original default match | 537 words | bounded |

The CPU total adds mean native AtomVM frame time to mean C raster time.
It excludes SPI transfer, FreeRTOS scheduling, display parsing/queue allocation
and the rest of the firmware. These are measured native improvements, not a
claim of 18× speed on the physical badge or proof that its crash is fixed.
The complete host suites pass; real firmware UI integration also verifies
crash recovery and that a stalled UI queues at most one rendering tick.

## Memory and the reported crash point

The first match is deterministic: tick 97 has blue/yellow scores 2,425 and
energy 147. The exact state renders and advances past that point on native
AtomVM. No matching native crash was observed.

Four badge presets, a fully filled board, repeated entry/settings/exit, and
100 complete rounds pass at each of 4,096, 8,192 and 16,384 heap words, without
an allowed OOM exception. Native words are eight bytes; badge words are four.
The resource runner samples `erlang:memory(binary)` separately because heap
limits and `flat_size` exclude off-heap binary payloads. Repeated-round peak sampled
binary usage at frame boundaries is below 17 KB. A separate fixture retains 32 consecutive rendered
frames, matching the driver's maximum queue depth: it passes at 32,768 heap
words and peaks at 475,276 sampled binary bytes. Tests enforce 350 KB for normal play
and 1 MB for the retained-frame case.

The bitmap adds a fixed off-heap buffer; the live-heap reduction is not an
89% reduction in total RAM. Native measurements exclude other badge processes,
fonts, radio tasks, DMA and driver allocations. Physical internal-RAM behaviour
remains a later check.

## Knockout follow-up

The follow-up replaces the expanding pixel burst with a brief `BAA!` in the
eliminated goat's round-score slot. Its numeric score returns after six frames;
scoring and collision blasts are unchanged. The shrinking fence now flashes
using its existing four border segments instead of individual ring marks.
Blast and trail clearing batch bitmap deletions rather than copying the entire
board once per removed cell.

Compared with committed build `9d0a21b`, the same six knockout frames at ticks
31–36 on the pinned tools give these mean costs:

| Work | Before | After | Improvement |
| --- | ---: | ---: | ---: |
| Native frame construction | 581.7 µs | 97.8 µs | 5.95× |
| Pinned C raster | 863.1 µs | 210.8 µs | 4.10× |
| Construction + raster | 1,444.8 µs | 308.6 µs | 4.68× |
| Warning construction at tick 240 | 1,245 µs | 100 µs | 12.45× |
| Peak drawing commands during these knockouts | 125 | 23 | bounded |

The benchmark now samples each knockout frame, the terminal frame and a
synthetic pre-contraction warning. Batched clearing did not materially change
native gameplay CPU in this run; its benefit is fewer full-board copies.
These measurements exclude hardware display transfers and scheduling.
Logs and all 207 rasterized scenes are in
`/private/tmp/beamwars-readiness/goatwars-death-benchmark`.

## Repeat the local measurements

Run from this apps worktree. The pinned native tools are already available on
this computer under `/private/tmp/beamwars-readiness`; results go under `_build`.
These commands never open a serial port.

```sh
export ATOMVM_SOURCE=/private/tmp/beamwars-readiness/AtomVM
export ATOMVM_BUILD="$ATOMVM_SOURCE/release"
export ATOMVM_BOOT_PACK=/private/tmp/beamwars-readiness/base-release/boot.avm
export ATOMGL_SOURCE=/private/tmp/beamwars-readiness/atomgl-inspect
export GOATWARS_RESULTS="$PWD/_build/goatwars-performance"

mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- ./scripts/goatwars_benchmark.sh
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- ./scripts/goatwars_raster.sh "$GOATWARS_RESULTS"
```

The first script archives the baseline from Git into the result directory,
compiles both versions and runs the same harness. The comparison rejects
incomplete results, different word sizes or different workloads, and fails
below 10×. The second script compiles the exact driver's scanline functions,
checks crop/scaling/RGBA colors against literal RGB565 pixels, and includes
raster CPU in the same 10× gate. Retain `baseline/results.log`,
`current/results.log` and both `raster.log` files as evidence.

For compatibility, memory stress and the actual USB image split:

```sh
./scripts/goatwars_install.sh --build-only
export GOATWARS_USB_OUTPUT="$PWD/_build/goatwars-usb"
export GOATWARS_RESULTS="$PWD/_build/goatwars-native"
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- ./scripts/goatwars_native.sh
```

The last command checks imports/instructions against the VM, loads the Store
pack with the released boot library, runs the memory fixtures, then loads
both actual USB packs and plays through tick 97 to the terminal tick 207.

## Device measurements later

Use [the installer](goatwars-usb.md) when ready. Normal play starts in bitmap
mode with logging off. Press **T** in the game to enable diagnostics. Every ten
ticks, and at tick 97, `GW_DEVICE` log lines report gameplay CPU, render CPU,
frame gap, heap words and UI queue length. Settings' Log tab receives them.
Press **M** while diagnostics are enabled to restart with legacy map rendering;
press M again for bitmap rendering. Each switch uses seed 1 and resets scores
so the two runs display the same workload. Legacy mode can still be slow.
Press T to stop logging; R then resumes ordinary rematches in the selected mode.
Leaving and reopening the game restores the bitmap default.

A later physical pass should confirm approximately ten ticks per second,
responsive turn keys, survival through tick 97 and several rematches, and
stable memory. Frame gap includes callback/display wait and ticker cadence;
render CPU measures list construction, not asynchronous SPI drain.
