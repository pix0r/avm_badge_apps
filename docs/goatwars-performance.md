# GoatWars performance verification

## Store firmware app corrections, October 2

The app waits for each completed step to reach its render callback before
replacing it. A new game frame starts the selected steering interval; repeated
status redraws do not restart it. During that interval, one monitored worker
prepares AI choices and previews the next complete step. At the deadline, the
page publishes that preview if there is no buffered human turn. A late turn
reuses the prepared AI choices and recomputes movement with the latest human
commands and controller ownership. Pause, settings, rematch and leaving cancel
both paths; stale worker results are rejected. Pure simulation clocks and seeded
replays are unchanged.

The default remains a 200 ms steering interval. Calculation overlaps that
interval instead of always being added after it. UI scheduling and display time
still affect actual movement, so this is not a five-frames-per-second claim.
Redraws use the stock UI ticker; no synthetic human-key events are sent and the
firmware's scheduler count remains unchanged.

Bitmap reads validate the exact RGBA colors with short-circuit byte reads.
SimpleBot skips side candidates only when its straight score cannot be beaten,
and scans long empty bitmap lanes by byte offset. The fallback preserves map
boards and malformed/unknown-pixel behavior. Clear-cell patching shares one
pixel binary. Fixed seeded replays, all headings and nearby interception choices
remain covered by app tests.

A bounded capture on unchanged published Store firmware recorded 109 completed
steps in the initial four-player phase and 97 in the dedicated two-player phase.
Every increasing tick reached the app render callback. While all four were
alive, step gaps had a 335.5 ms median and 406.7 ms p95, versus 496.5 ms in the
preceding timer-only build. The two-player phase measured 316.8 ms median and
399.2 ms p95, versus 435.9 ms before previewing. The four-alive sample contains
nine gaps; the two-player sample contains 96. No watchdog or crash was recorded.
This measures app frame materialization, not physical panel completion. Human
confirmation is still required to establish pre-switch gameplay feel.

A longer run completed 316 M Square steps and 179 XL Wide steps, with every
step reaching the render callback before the next replaced it. Four-alive median
gaps were 316.2 ms over 36 M Square samples and 332.0 ms over 178 XL Wide samples.
No watchdog or crash occurred during the 207-second active sequence. Reported
free heap recovered from roughly 1.93 MB during play to 2.03 MB after Home;
this is total heap, not a measurement of internal RAM.

A wall fixture uses the real UI, normal title/countdown and a human P1. It injects
a turn after the first frame is prepared, with P1 one step from a wall. All four
left/right repetitions survive. Key acceptance measured 67–111 ms; movement
with that turn completed 251–366 ms after injection. The injected UI event does
not include physical keyboard scanning or a player's reaction time.

223 app tests pass. The pinned native VM resolves all imports and 63 instructions
across 21 source modules; the actual Store pack and split USB images load and
exercise preview publication, late input, cancellation and worker failure.
The optimized board/controller revision also passes 2,400 seeded rounds across
all eight board geometries and three heap caps, plus 32 retained-frame fixtures.
No firmware test suite was run. Selected app modules omit bytecode line markers
to fit the Store limit; private function metadata remains present.

The Store pack is 65,524/65,536 bytes; USB main is 638,808/671,744 and assets are
262,144/262,144. Published Store firmware remains pinned to
`bf0cc9621b5fe9543a2c600ae43115e87fc78156`, with no source or index changes.
The physical VM's boot ELF SHA matches published badge-v1 image metadata.

Excluded hardware experiments include packing the whole page state into a binary
(which worsened pacing), parallel AI (little consistent full-step gain), and
scheduler-count changes (watchdog reports during longer play). No scheduler
experiment is part of the release.

After app-side experiments, the unchanged contributor head of
[Pong support PR #2](https://github.com/mwingert/avm_badge/pull/2),
`fe03f0ba4710e22859bd53ddfb072f53796001d7`, was measured separately. Its 50 ms
UI ticker and tick backpressure gave 459.5 ms four-alive and 418.1 ms two-player
medians on the timer-only app, a modest improvement. That older Store firmware
is excluded; the final app preview runs on the current published Store revision.

Evidence is under `/private/tmp/goatwars-perfect/`: `preview-green2.log`,
`preview-native/`, `pipeline-full/`, `preview-frames-device.log`,
`preview-frames-four.json`, `preview-frames-two.json`,
`preview-input-device.log`, `soak-device.log`, `preview-soak-four.json`,
`preview-soak-xl_wide.json` and `pong-frames-device.log`. Temporary diagnostic
launchers are absent from the normal install image.

## UI overload measured on the badge, October 2

The refresh correction below did not resolve physical playability. A bounded
hardware probe reproduced the problem on the installed build: four-player steps
could exceed 200 ms while the upstream UI keeps sending 100 ms timer messages.
Running the calculation inside `Badge.UI` caused its mailbox to grow beyond 300
messages, delaying input and display updates by many seconds.

GoatWars now dispatches one monitored app-owned worker per due step and returns
from `tick/1` immediately. The page accepts its result through `handle_info/2`;
there is never more than one pending calculation. The countdown's first step
uses the same path. Pause, settings, rematch and leaving cancel the worker;
identity checks reject cancelled results. Steering received while a step runs
stays buffered for the following step. No firmware source patch is involved.

Two complete on-device worker runs kept the UI mailbox bounded during play:
0–6 messages with the original controller memory and 0–7 with compact policy
memory. Startup still briefly reached approximately 25 queued messages while
artwork and the initial match were prepared. SimpleBot retains only its two
used policy fields, reducing each controller memory from 34 to 16 heap words;
its deterministic decisions are unchanged. A 4,096-word initial worker heap
made timing worse on hardware and was removed.

Four-player worker timing at tick 10 was approximately 193–216 ms; two-player
steps were generally around 95–140 ms. These are elapsed worker times, including
scheduling, rather than isolated CPU measurements. Completed steps often remain
200–300 ms apart. The selected default is still 200 ms; this does not establish
constant five-frame-per-second physical output. Human confirmation of gameplay
feel remains necessary. Diagnostic logging now changes state only on completed
steps, rather than forcing a draw on every UI tick.

211 app tests and 18 Python checks (three optional pixel cases skipped) pass.
The strict native audit resolves all runtime imports and 63 instructions across
21 source modules. Actual Store and split USB images load, play and exercise
both normal and first-step asynchronous callbacks on the pinned AtomVM. The
runtime pack excludes the unused Input helper and Controller behaviour module;
all runtime game imports remain present. No firmware test suite was run.

The final Store pack is 64,276/65,536 bytes; USB main is 637,560/671,744 and
assets are 262,144/262,144. Firmware source and index match the published
`bf0cc9621b5fe9543a2c600ae43115e87fc78156` Store checkout. Temporary diagnostic
launchers were used only for measurement and are absent from the final image.
Evidence is under `/private/tmp/goatwars-pace/`: `device-baseline.log`,
`device-async.log`, `device-compact.log`, `final-tests.log`, `final-python.log`
and `final-native/`.

## Frame pacing correction, October 2

The clean upstream UI ticks at 100 ms and uses `refresh/1` only to throttle
painting. GoatWars also gates movement against its own clock. Returning the
200 ms game step from both callbacks added a second frame delay: a reproduction
with 220 ms callback gaps showed steps 1, 3 and 5, skipping 2 and 4.

The app now requests drawing within 100 ms while retaining the selected game
step duration. The same reproduction displays steps 1 through 5. The regression
covers four and two active players; 204 apps tests passed at that revision. Native checks load and
play the actual game and split USB archives with the unchanged upstream firmware.
This was insufficient on the physical badge; the overload fix above follows it.

## Default pace, October 2

Badge play now defaults to 200 ms per step (five steps per second), down from
100 ms. Four and two active players use the same requested cadence. Settings
retain 10 ms F/V adjustments over 50–400 ms, and rematches retain the selected
speed. The latest 23×23 M Square default, all Square/Wide presets, artwork,
deferred startup and obstacle-avoidance AI remain in place.

A failing-first clock test covers both player counts, boundaries before each
step, and rematches. Native readiness checks the same 200 ms boundaries.
The firmware home-grid test was removed; packaging tests remain.

The final USB build uses unmodified published Store firmware
`mwingert/avm_badge`, `feature/add-app-store-rebased`, at `bf0cc96`. The local
cadence and firmware test fixes are excluded. Its UI ticker remains 100 ms;
sub-100 ms game settings do not imply an equally fast display cadence.
That revision’s game pack was 65,532/65,536 bytes; USB main was 638,816/671,744
and assets were 262,144/262,144. Current sizes are recorded above.

Version 0.1.6 defaults to **M Square**, 23×23 cells at 8 pixels per cell,
with a 2,116-byte opaque RGBA bitmap. Settings G cycles S/M/L/XL and A switches
Square/Wide. Step durations remain 50–400 ms in 10 ms increments (F slower,
V faster). Enter applies the draft; S cancels; rematches retain all choices.

| Size | Square | Wide | Cell pixels |
|---|---|---|---|
| S | 14×14 | 24×14 | 13 |
| M | 23×23 | 39×23 | 8 |
| L | 30×30 | 51×30 | 6 |
| XL | 46×46 | 78×46 | 4 |

The square arena gives each edge the same room. Even-sized squares alternate
between the two central edge cells so spawns match under a 90-degree rotation.
Rendering fits custom dimensions to 312×184 pixels; the HUD stays outside that area.
M Square uses 65.4% fewer board bytes than the previous 51×30 default.

## Deferred startup

Opening GoatWars returns a small loading state before decoding artwork or
building the match. The first tick submits “Loading GoatWars...” and the next
prepares the title. Enter starts the existing three-second countdown. Home
navigation can cancel loading; initialization options survive preparation.
Preparation remains synchronous after the loading frame is submitted.

The current artwork decoder is retained. Startup tests cover deferred work,
frame ordering and custom options; firmware UI integration covers Home
cancellation and reentry. All 198 apps tests and eight firmware UI scenarios
pass. The strict native audit resolves all imports across 21 modules, and the
65,140-byte Store pack loads and plays on AtomVM. The offline USB fixture is
668,044/671,744 bytes in main and 262,144/262,144 in assets.
Physical visibility needs a badge check.

## No-grid purple palette, October 2

Version 0.1.6 removes gameplay grid lines in both map and bitmap renderers.
The board background changes to `#3D175A`, slightly lighter than `#32104F`,
and P1's laser changes to bright purple `#C840FF`. Player IDs still encode and
decode consistently; single and batch trail deletion restore the new background.
P2/P3/P4 remain green, pink and violet. White heads remain visible over the trails.

The bitmap scene returns to one board image, up to four heads and four fence
commands. Full gameplay pages emit at most 26 items, down from 42 on XL Wide.
Empty map and bitmap pens emit exactly five items at every tested size and inset.
No geometry, timing, AI, artwork or retained bitmap size changes.

195 host tests and seven fake-hardware firmware UI scenarios pass, including
unchanged sixteen deterministic AI replay fixtures. The strict native audit
resolves all imports and 63 instructions in 21 modules. The Store pack is
64,656/65,536 bytes, 676 bytes smaller than version 0.1.5. USB main is
667,492/671,744 bytes; assets remain 262,144/262,144. Both actual Store and split
USB packs load and play on the pinned native VM. The constrained-memory suite
passes 2,400 seeded rounds across all eight geometries and three heap caps.

The actual C driver framebuffer was sampled and inspected: the former grid
positions now have the uniform background, P1 is bright purple, and the other
three trail colors are preserved. Evidence and preview:
`/private/tmp/beamwars-readiness/goatwars-no-grid-native/board.png`.
No hardware was accessed. The grid benchmark below records version 0.1.5,
not the current appearance.

## Space-efficient AI and purple laser grid, October 2

Version 0.1.5 stops proximity chasing and idle random turns. Short projected
route intersections still allow cutoffs. When straight travel is unsafe, the bot
scans the two clear turning lanes to the next obstacle or fence and chooses the
longer one. This includes an occupied forward cell, an approaching head, and a
clear cell with no onward escape. Ray scans are tail-recursive and bounded by
board dimensions; cruising retains the two-cell safety check. A blocked XL Wide
bot decision is capped at 1,800 host reductions. Four-goat early frames remain
within the existing 1,250-reduction guard. These are work guards, not badge timing.

The board is richer purple with one-pixel grid lines every eight cells. The
compact path overlays at most 16 lines on XL Wide, with white heads above the
lines. Trails are saturated gold, green, pink and violet; their bitmap encoding
and collision IDs agree. Gameplay pages emit at most 42 items. The goat on pause,
win and draw screens is 96×64 at (112,136), half the title scale and clear of the
score panel. It reuses the same cached RGBA binary.

AI routes and round lengths intentionally change, so whole-round comparisons
across this policy boundary are rejected. The opt-in fixed-input benchmark uses
four identical literal head/obstacle setups on both revisions and repeats one
advance/render from each immutable state 1,000 times. The actual C display driver
then rasterizes each resulting scene. Compare against `501f38a`:

| Fixed fixture | Before construction | Current construction | Before raster | Current raster |
|---|---:|---:|---:|---:|
| M Square cruising | 457 µs | 443 µs | 73 µs | 110 µs |
| M Square, all four forced to turn | 438 µs | 626 µs | 73 µs | 108 µs |
| XL Wide cruising | 465 µs | 471 µs | 91 µs | 264 µs |
| XL Wide, all four forced to turn | 442 µs | 965 µs | 87 µs | 263 µs |

Cruising construction is approximately unchanged. Forced turns cost more because
they inspect full lanes; the grid also increases raster work, especially on XL.
Including raster, M cruising is about 4% slower and XL cruising about 32% slower
in these fixtures. This is a functionality tradeoff, not a new performance gain.
The native VM is 64-bit on a desktop; these values do not predict ESP32 frame time.

Run with the pinned VM/boot/driver environment from the commands below:

```sh
GOATWARS_BASELINE_REF=501f38a GOATWARS_FIXED_WORKLOAD=1 \
GOATWARS_MIN_SPEEDUP=0.25 GOATWARS_RESULTS=/tmp/goatwars-space-bench \
  ./scripts/goatwars_benchmark.sh
GOATWARS_FIXED_WORKLOAD=1 GOATWARS_MIN_SPEEDUP=0.25 \
  ./scripts/goatwars_raster.sh /tmp/goatwars-space-bench
```

The 0.25 threshold checks that no fixture is more than four times slower; it is
not a speedup claim. The default whole-round gate is unchanged. Fixed fixture
generation is explicitly opt-in so old baselines and saved raster results still
run without newer helper APIs. Fixtures reject missing/duplicate cases, mismatched
runtimes or repetition counts, and incomplete driver measurements.

195 apps tests, seven firmware UI integration scenarios, and 15 Python/native
pixel tests pass. The strict AtomVM gate resolves all imports and 63 instructions
in 21 game modules. Store pack: 65,332/65,536 bytes. USB main: 668,168/671,744;
assets: 262,144/262,144. Native Store and actual split USB images load and play.
The memory stress suite passes 2,400 seeded rounds across eight geometries under
4,096/8,192/16,384-word caps. Peak retained soak state is 636 words; sampled
binary memory peaks at 65,580 bytes. M Square peaks at 50,600 bytes; the 32-frame
M queue peaks at 118,308 bytes and XL Wide at 524,844. No extra artwork or board
cache was added. Native results exclude total ESP32 internal RAM/PSRAM usage.

Evidence: `/private/tmp/beamwars-readiness/goatwars-space-native` and
`/private/tmp/beamwars-readiness/goatwars-space-final-benchmark`. Actual framebuffer
samples verify the background, both grid axes, four trail colors and head highlight.
Board and result PNGs in `goatwars-space-benchmark/current` were inspected. No badge was
accessed or flashed.

## Further CPU optimization, October 2

The baseline is the current AI/artwork build `fb8d65c`, preserving those newer
commits. Shared opponent routes remove duplicate forecasts across goats; bounded
runway checks and direct bitmap decoding reduce per-step work. Sixteen recorded
seed/size replays remain identical. A failed-first host budget now caps a
four-goat advance/render at 1,250 reductions, down from a 2,500 limit. Artwork
loading fell from about 25,108 to 10,270 host reductions while preserving both
SHA-256 pixel hashes. Host reductions measure work, not badge timing.

Firmware caches the Backlight sleep timeout and receives updates on save or
process restart. Gameplay frames no longer synchronously call Backlight.settings.
A suspended Backlight process no longer blocks a game frame. The asynchronous
startup handshake also supports UI starting before Backlight.

The final same-workload comparison against `fb8d65c` ran five 78×46 rounds,
1,320 ticks, and all 264 actual C raster frames:

| Measured work | Before | After | Gain |
|---|---:|---:|---:|
| Page initialization | 14,893 µs | 3,723 µs | 4.00× |
| Mean gameplay + frame construction | 588.41 µs | 444.89 µs | 1.32× |
| Mean native raster | 88.61 µs | 88.92 µs | approximately unchanged |
| Construction + raster | 677.02 µs | 533.81 µs | **1.27×** |

The **2× gameplay gate fails**. This is an improvement, not achievement of that
target. Initialization is measured separately; artwork decoding is excluded from
the gameplay loop because rematches reuse it. Seven framebuffer hashes, including
tick 97 and the terminal artwork frame, match the baseline. The comparison uses
identical full-size rounds; changing the default size is not counted as CPU gain.
An earlier batched-head-copy prototype increased code size without a useful
whole-round benefit and was removed.

All eight size/aspect combinations pass 100 seeded rounds at each of
4,096/8,192/16,384 heap words: **2,400 rounds** total. Peak retained page state
in those soaks is 631 words; sampled binary memory peaks at 66,716 bytes. The
M Square soak peaks at 50,916 binary bytes, and its 32-frame retained queue peaks
at 118,048 bytes (XL Wide queue: 523,548). These are native 64-bit VM measurements,
not total ESP32 RAM/PSRAM usage.

188 apps tests, 1,408 firmware tests (two asset cases excluded), seven fake-hardware
UI scenarios, nine Python comparison/installer tests and three native pixel tests
pass. The Store pack is 65,476/65,536 bytes. USB firmware is 668,312/671,744 bytes;
assets are 262,144/262,144. Actual split images and Store pack load and play on
the pinned VM with the released boot pack. AtomVM imports and all 63 instructions
in 21 game modules resolve; firmware checking reports 30 known warnings, and the whole-app check reports 38.
The strict game audit resolves every runtime import.

Evidence: `/private/tmp/beamwars-readiness/goatwars-square-final-benchmark` and
`/private/tmp/beamwars-readiness/goatwars-square-final-native`.
No badge was accessed. SPI transfer, scheduler contention and physical gameplay
feel remain unmeasured; removal of the blocking Backlight call is not assigned a
synthetic physical speedup.

## Earlier middle board and configurable pace

Version 0.1.3 uses 10 ms adjustments, F slower and V faster, bounded at 50–400 ms.
The earlier 100 ms floor was the firmware ticker, not a measured panel limit.
An optional `tick_interval/1` lets this game select its cadence; other pages
retain 100 ms ticks. Paused, countdown, settings and result screens also use
100 ms. UI render backpressure remains in place and its sleep/status counters
scale with the requested interval. Fine deadlines retain phase through small
callback jitter; a long stall advances once and resets the deadline.

The new paired USB firmware is required to honor fine and sub-100 ms speeds.
At 50 ms the requested rate is 20 steps/frames per second, subject to VM,
display and scheduling time. This was not measured on physical hardware.
159 game tests, 1,408 firmware tests (two asset-regeneration cases excluded),
five integration scenarios, 11 script tests and the strict native game gates
pass. Final USB/native evidence is under
`/private/tmp/beamwars-readiness/goatwars-fine-speed-final-native`.

After the small board proved too fast in physical play, version 0.1.2 added the
arithmetic midpoint 51×30 as the default. Its cells are 6 pixels wide versus
13 for 24×14 and 4 for 78×46. The bitmap is 2.35× smaller than the original.
Movement remains one cell per step; configurable step durations slow it without
changing collision, scoring or AI rules. Default 100 ms steps are unchanged.
The first middle-board match ends at tick 90. Original tick-97 regression checks
still use the explicit full-size board.

Controls default to Left/Right arrows, Z/X, 1/2 and 9/0. C still cycles unique
key pairs, swapping the other assignment when necessary. The new settings and
controls have failing-first host tests and native AtomVM lifecycle checks.
The repeatable USB images contain the new default; no badge was accessed.
157 host tests, 11 Python checks and four firmware UI scenarios pass. Native
stress covers 900 rounds across all three sizes. Middle-board peak sampled
binary usage at frame boundaries is 8,500 bytes; retaining 32 rendered frames
peaks at 202,684 bytes. These are not total badge RAM measurements. Latest native
and actual USB-image evidence is in
`/private/tmp/beamwars-readiness/goatwars-middle-native`.

## Earlier smaller-board fallback (`3df68da`)

The new request was another 5× CPU improvement or a lower-resolution board.
Against the committed knockout fix `50696f1`, optimization reached 1.79× for
native gameplay, rendering and C raster combined. The 5× performance gate
correctly fails. The delivered default therefore uses the requested smaller
board; this is not a claim of another 5× CPU improvement.

Both versions run the same five full-size rounds, 1,035 ticks, and all 207 C
raster frames on the pinned tools below. Shorter small-board matches do not
count toward the CPU comparison.

| Work | `50696f1` | `3df68da` | Improvement |
| --- | ---: | ---: | ---: |
| Five full-size rounds: advance + render | 368,599 µs | 240,613 µs | 1.53× |
| Mean C raster per full-size frame | 219.5 µs | 88.5 µs | 2.48× |
| Mean combined CPU per full-size frame | 575.7 µs | 320.9 µs | 1.79× |
| Board bitmap bytes | 14,352 | 1,344 | 10.68× smaller |
| Peak sampled binary bytes with 32 retained frames | 475,276 | 45,084 | 10.54× smaller |

Gameplay uses fewer intermediate maps and traversals; unchanged controller
memory and empty trail cleanup reuse their state. Opaque score and overlay text
avoid the driver's search through underlying drawing items at blank glyph pixels.
The native driver pixel tests cover both opaque text and scaled bitmap colors.

The smaller board retains the 100 ms step and uses 13-pixel cells rather than
4-pixel cells. Movement covers 3.25× more screen distance per tick. At the same
four-goat tick-4 state, native advance/render takes 282 µs at either resolution;
C raster takes 92.2 µs for 24×14 and 90.3 µs for 78×46. Lower resolution primarily
reduces bitmap copying and memory, not full-screen raster work. Physical speed
and responsiveness still need the user's device test.

Settings show `G: Board 24x14` or `78x46`; Enter applies the choice and recomputes
layout and the initial fence deadline. Rematches retain it; S cancels changes.
Reopening the page restores 24×14. The first default round ends at tick 91;
the original full-size round still ends at 207, including the exact tick-97
scores/energy regression.

153 host tests, 11 Python tests, four real firmware UI integration scenarios,
the strict 19-module/59-instruction AtomVM audit, Store loading, and the actual
split USB packs pass. Native stress runs 100 rounds in each board size at each
of three heap caps: 600 complete rounds. Peak sampled binary usage during
coarse rounds is 2,156 bytes versus 16,628 for full-size rounds. Samples are at
frame boundaries, not transient allocation high-water marks or total badge RAM.
Both modes also pass with 32 rendered frames retained.

Final evidence is under
`/private/tmp/beamwars-readiness/goatwars-coarse-verified-benchmark` and
`/private/tmp/beamwars-readiness/goatwars-coarse-verified-native`.

## Earlier full-size baseline and results

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

The first full-size match is deterministic: tick 97 has blue/yellow scores 2,425 and
energy 147. The exact state renders and advances past that point on native
AtomVM. No matching native crash was observed.

Four badge presets, a fully filled board, repeated entry/settings/exit, and
100 complete rounds in each size pass at each of 4,096, 8,192 and 16,384 heap words, without
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
export GOATWARS_BASELINE_REF=fb8d65c
export GOATWARS_MIN_SPEEDUP=2

mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- ./scripts/goatwars_benchmark.sh
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- ./scripts/goatwars_raster.sh "$GOATWARS_RESULTS"
```

The first script archives the baseline from Git into the result directory,
compiles both versions and runs the same harness. The comparison rejects
incomplete results, different word sizes or different workloads, and fails
below 10×. The second script compiles the exact driver's scanline functions,
checks crop/scaling/RGBA colors and opaque text against literal RGB565 pixels, and includes
raster CPU in the same 10× gate. Retain `baseline/results.log`,
`current/results.log` and both `raster.log` files as evidence.

To repeat the latest follow-up comparison instead, set these before the two
benchmark commands. Its 5× gate fails, as documented above; the smaller-board
fallback is validated by the resource and packaging checks.

```sh
export GOATWARS_BASELINE_REF=50696f1
export GOATWARS_MIN_SPEEDUP=5
```

For compatibility, memory stress and the actual USB image split:

```sh
./scripts/goatwars_install.sh --build-only
export GOATWARS_USB_OUTPUT="$PWD/_build/goatwars-usb"
export GOATWARS_RESULTS="$PWD/_build/goatwars-native"
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- ./scripts/goatwars_native.sh
```

The last command checks imports/instructions against the VM, loads the Store
pack with the released boot library, runs the memory fixtures, then loads
both actual USB packs and plays both the default round to tick 91 and the
full-size round through tick 97 to terminal tick 207.

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
