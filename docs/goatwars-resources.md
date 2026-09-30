# GoatWars resource testing

## Snake hardware report — 2026-09-29

Mike relayed this report from Mathias Wingert, author of the Snake game:

> I created the package and merged your PR. The game is in the store. I tried to start it on the device, downloading fails sometimes due to the size and the limitation of the internal ram. When it loads both CPU cores stay 100% busy running code and the badge stops responding, `Watermark.sprite/1` seems to be the culprit.

This is a reported hardware observation, not a diagnosis independently reproduced
here. Download memory pressure and runtime CPU saturation are separate problems.
The inspected Snake PR worktree builds a 79×22 RGBA watermark each frame: 1,738
pixels and 6,952 output bytes. Its per-pixel path includes sine calculations,
palette lookup and binary construction. That is a plausible hotspot; measure
with the watermark disabled before attributing the whole failure to it.

## Implications for GoatWars

GoatWars has no dynamic RGBA sprite generation or per-pixel trigonometry. That
avoids the specific Snake workload, but does not establish hardware readiness:

- Four AI decisions can occur together, synchronously inside Badge.UI. The
  delayed decision model changes cadence, not CPU scheduling or computation cost.
- Occupancy maps, path lists and replay history retain terms; explosions permit
  revisiting cells, so path history is not bounded by occupied-cell count alone.
- Rendering sorts occupied cells and compresses horizontal runs. Vertical or
  fragmented trails can still produce thousands of display items per frame.
- A full-panel repaint at 10 Hz can outrun the display driver. The local
  Badge.Page documentation explicitly warns that queued frames consume heap.
- Package download/loading, fonts, display buffers and Wi-Fi use memory beyond
  the game process. A small application heap cap cannot cover these allocations.

Before shipping, measure bounded replay or disable replay on the badge, cap AI
work and move expensive decisions off the UI process if necessary. Consider a
compact occupancy representation and compression in both axes if dense-board
measurements require it. Guest controllers should run on a host with deadlines;
trusted local code currently runs synchronously.

## Measurements already taken

Elixir 1.18.3 / OTP 27 on this development computer, 78×46 board. These are host
measurements, not predicted ESP32 memory or frame times. The dense fixture assigns
alternating player colors to every cell; it tests renderer stress and is not
claimed to be a naturally reached match state. State includes occupancy and paths;
word counts use `:erts_debug.size/1` and exclude VM/driver overhead and transient
allocations. Host words are 8 bytes; AtomVM layouts and allocation differ.

| Fixture | Occupied cells | State host words | Display items | Display-list host words | Render time, one host sample |
| --- | ---: | ---: | ---: | ---: | ---: |
| Launch | 4 | 160 | 29 | 261 | 19 µs |
| Dense alternating colors | 3,588 | 31,394 | 3,613 | 32,517 | 1,553 µs |

Thirty fresh four-bot first ticks per preset: median host times were 280 µs
(novice), 616 µs (intermediate), 1,129 µs (expert), and 2,160 µs (pro).
These measure the game/AI path, not display drain. Desktop timings must not be
scaled by a guessed CPU ratio to claim the badge meets a 100 ms deadline.

## What can be simulated without a badge?

1. **Existing browser and host tests:** gameplay, appearance and deterministic
   replay. They use Erlang/OTP, not AtomVM, and are not a resource emulator.
2. **The badge-v1 AtomVM fork on Generic UNIX:** compile and pack a headless
   entry point against the same fork's standard libraries. Run seeds and dense
   render fixtures in a worker spawned with `max_heap_size`; sweep limits and
   report failures, collections and work. This exercises real AtomVM semantics
   and GC under an explicit process budget. Use only functions supported by the
   fork. A native 64-bit build still differs from the badge's word sizes; a
   32-bit build is closer where the host toolchain supports it. Per-process caps
   do not constrain all binaries, native driver allocations or Wi-Fi memory.
3. **Espressif ESP32-S3 QEMU:** runs the chip instruction set and emulates RAM,
   flash, dual-core CPU and PSRAM. This is a closer firmware-level option. The
   official feature table lacks general-purpose SPI, GPIO matrix, Wi-Fi and
   Bluetooth, so the badge's ST7789 SPI display and networking are not drop-in
   peripherals. Build a headless/test firmware or provide adapters, with the
   actual badge RAM/PSRAM configuration. QEMU is not a cycle-accurate benchmark
   proving real display or RF performance.
4. **Physical badge acceptance:** repeated store downloads, start/stop, long
   rounds, four bots, all deaths together, Wi-Fi on/off and network load. Record
   free heap, minimum free heap, largest contiguous block, tick/AI/render time,
   UI mailbox length and input latency. Match image/API support before enabling
   counters. A falling free heap or growing queue is a failure even if play looks
   smooth initially.

Neither native AtomVM nor Espressif QEMU is installed in this workspace's current
PATH. Those constrained runtime tests have not been run. The current whole-project
AtomVM checker stops before validation because of a host-only dependency in the
badge build; Store packaging also needs firmware-version alignment.

References:

- [AtomVM Generic UNIX setup](https://doc.atomvm.org/main/getting-started-guide.html)
- [AtomVM process heap options and ESP32 memory counters](https://doc.atomvm.org/main/programmers-guide.html)
- [Espressif QEMU ESP32-S3 guide](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32s3/api-guides/tools/qemu.html)
- [QEMU supported peripherals](https://github.com/espressif/esp-toolchain-docs/blob/main/qemu/README.md)
- [Local Badge.Page refresh contract](../../avm_badge/lib/badge/page.ex)
- [Local power/free-heap reporting](../../avm_badge/lib/badge/power.ex)

Current measured native results and readiness limits are recorded in
[the readiness report](goatwars-readiness.md); earlier estimates here are not
physical-device measurements.
