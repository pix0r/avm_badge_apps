# GoatWars

A four-goat trail game inspired by Steve Crutchfield's Macintosh lightcycle game.
The pure Elixir engine runs without a badge, display, network, clock, or processes.
The browser uses the real badge page API through the sibling firmware's simulator.

## Architecture

- **Runtime:** Elixir runs on AtomVM on the ESP32-S3. The firmware's
  [`Badge.UI`][ui] GenServer owns the [page state](lib/badge/app/goatwars/page.ex) and calls `Page.handle_key/2`,
  `tick/1` and `render/1`; GoatWars has no separate game process.
- **Title and other screens:** [`Page.render/1`](lib/badge/app/goatwars/page.ex) selects title, countdown, gameplay,
  pause and results. [`Art.load/0`](lib/badge/app/goatwars/art.ex) decodes embedded RLE pixel art after the loading frame;
  [`Render.Interstitial`](lib/badge/app/goatwars/render/interstitial.ex) combines it with text and rectangle scenery.
- **Gameplay:** [`Match.tick/1`](lib/badge/app/goatwars/match.ex) gathers queued human turns and [`SimpleBot`](lib/badge/app/goatwars/simple_bot.ex) decisions,
  then calls the pure [`Game.step/2`](lib/badge/app/goatwars/game.ex) for simultaneous movement, collisions,
  explosions, trail retraction and arena shrinking. `Match` tracks round
  points and bonus; `Page` handles timing, rematches and cumulative scores.
- **Drawing:** AtomGL is the badge's 2D display-list renderer; GoatWars uses
  no OpenGL/WebGL API or shaders. [`Board`](lib/badge/app/goatwars/board.ex) stores one RGBA pixel per cell.
  [`Render.scene/3`](lib/badge/app/goatwars/render.ex) returns a scaled board image plus head/border rectangles;
  [`Page.hud/1`](lib/badge/app/goatwars/page.ex) adds scores and labels. `Badge.UI` adds chrome and
  [sends the list to the native display port][display] for a full ST7789 repaint over SPI.
  Items paint tail-to-head: the first item is on top.
- **Scaling:** [`Render.layout/1`](lib/badge/app/goatwars/render.ex) centres the board in a 312×184-pixel area,
  using `max(1, min(312 ÷ width, 184 ÷ height))` with integer division.
  The default 23×23 preset therefore uses 8×8-pixel cells (184×184 pixels).
  [`scaled_cropped_image`](lib/badge/app/goatwars/render.ex) crops to the surviving arena and scales each source pixel by that cell size;
  [title/goat artwork](lib/badge/app/goatwars/render/interstitial.ex) reuses cached RGBA binaries.
- **Settings:** [`Setup`](lib/badge/app/goatwars/setup.ex) holds player modes, key bindings, board size, speed
  and retraction. The [settings handlers](lib/badge/app/goatwars/page.ex) edit a draft while play stops;
  Enter applies it to a new round and S discards it. Settings live in memory.
- **Browser and tests:** The same Elixir page runs on BEAM with fake hardware;
  Phoenix LiveView sends display items to [Canvas 2D][canvas] and keys back to
  `Badge.UI`. `drawImage` reproduces cropping/scaling with smoothing disabled;
  CSS displays the 320×240 canvas at 2× size. [Headless tests](../../scripts/goatwars_test.exs) drive `Match` and `Game` directly.

[ui]: https://github.com/mwingert/avm_badge/blob/cb019046f4acba55c0301ff86809b67bcdc87b3b/lib/badge/ui.ex
[display]: https://github.com/mwingert/avm_badge/blob/cb019046f4acba55c0301ff86809b67bcdc87b3b/lib/badge/display/atom_gl.ex
[canvas]: https://github.com/mwingert/avm_badge/blob/cb019046f4acba55c0301ff86809b67bcdc87b3b/sim/lib/badge/sim/live.ex

## Run

From the apps repository, with Elixir 1.18.3 / OTP 27 installed through mise:

```sh
# No dependencies or simulator needed for these:
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- elixir scripts/goatwars_test.exs
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- elixir scripts/goatwars_headless.exs --rounds 20 --level expert

# Browser (requires ../avm_badge and its dependencies):
./scripts/goatwars_sim.sh
```

On first setup, run `MIX_TARGET=host mix deps.get` in `../avm_badge` with the same
mise toolchain. The script accepts `AVM_BADGE_PATH` for a different firmware path.
Visit http://localhost:3240. Opening first shows a loading message while the title
is prepared. The title waits for Enter; four AI riders then launch
after a separate three-second board countdown with cannon launchers. Scores accumulate,
and completed rounds restart after two seconds. Two browser tabs share one board.
Exit the simulator's IEx with Ctrl-C, then `a`.

| Keys | Action |
| --- | --- |
| Enter, on the title | Start the countdown |
| Left / Right | Take over bright purple (player 1), turn left / right |
| Z / X | Take over neon green (player 2), turn left / right |
| 1 / 2 | Take over hot pink (player 3), turn left / right |
| 9 / 0 | Take over violet (player 4), turn left / right |
| Space | Pause / resume |
| R | New round, preserve total scores |
| S | Open / cancel player settings |
| B | Return all riders to default AI |
| T | Toggle performance timing logs |
| M, while timing is on | Restart seed 1 in legacy/bitmap mode |
| Esc, then F1 | Home, then reopen GoatWars |

In settings, Up/Down selects a player; Left/Right cycles Human, AI Simple and
Inactive. G cycles S/M/L/XL. A switches Square/Wide while keeping the size.
Square dimensions are 14×14, 23×23, 30×30 and 46×46; Wide dimensions are
24×14, 39×23, 51×30 and 78×46. F adds 10 ms to the step
duration; V subtracts 10 ms. The range is 50–400 ms; larger durations slow the
game. C cycles left/right key presets; choosing
an occupied preset swaps assignments. R toggles beam retraction. Enter applies
settings and starts a new countdown. At least two slots must be active. Settings
suspend the match; S cancels without applying changes and returns to the screen that opened them. Board size, aspect and speed are
independent; rematches preserve all three. Leaving and reopening restores defaults.

The title shows detailed goat/lightcycle art and “DON’T LET IT CRASH”. Pause, win
and draw screens show the cached goat at half the title scale, centered lower
above the score panel. The countdown shows the full board and launchers.
Artwork is embedded as RLE-compressed sixteen-colour pixel indices (3,748
bytes), decoded once when the page opens, and reused as RGBA binaries (46.5 KiB).
Stars and neon scenery are display primitives. The Elixir/Goatmire palette uses a
slightly lighter purple board without grid lines and saturated bright purple,
neon green, hot pink and violet trails. The app pack is 65,140 bytes, under the 65,536-byte
Store limit. The matching offline USB build has
3,700 bytes free in firmware and no free space in assets; rebuild and check both
sizes after changes.
The USB pack excludes host-only Mix tasks. [Artwork and extraction prompts](assets/source.json)
record the two sprites; PNG previews are excluded from firmware packs.
`Page.init(countdown_ms: 0)` skips loading, the title and countdown for tests and benchmarks.
`Page.init(loading: false)` prepares the title immediately for isolated title tests.

A keypress supplies one turn on the next tick; absent input maintains direction.
The last press before a tick wins. Held-key integration remains deferred.

## Rules and configuration

The badge preset is M Square: 23×23 cells, drawn at 8 pixels per cell, at
200 ms per step (five steps per second). Square spawns are rotationally symmetric, including even sizes.
Its fixed bitmap is 2,116 bytes with packed trails, rendered as one scaled image.
In settings, G cycles M → L → XL → S; A switches the selected size between
Square and Wide. Enter applies the draft, and S cancels it. F/V adjust speed
without changing the board. Custom width/height rules still fit automatically.
The paired USB firmware honors the chosen tick cadence, including below 100 ms;
older firmware ticks pages every 100 ms. Actual physical frame rate can be lower
than the requested rate if gameplay or display work takes longer.
[Performance verification](../../docs/goatwars-performance.md)
contains benchmarks and device timing instructions.

Bright purple starts at the bottom, green at the top, pink at the left and violet at the
right, facing inward.
The core accepts arbitrary rosters of two or more players through `Game.new/2`;
`Match.demo/3` supplies four edge spawns and requires dimensions at least 2×2.

All movement is simultaneous. Own trails, opponents' trails, old heads, walls,
and shared destinations kill a rider. The badge preset enables explosions with a two-cell radius and dead-beam
retraction at eight cells per tick. A crash clears nearby trail cells immediately,
after simultaneous collision resolution, while preserving surviving heads.
Retraction then removes the dead player's path from head back toward its cannon.
Set `explosion_radius: 0` and `retract_speed: 0` for permanent trails.
The last rider
wins; simultaneous elimination of the last riders is a draw. Each successful
surviving step earns 25 points. A crashing step earns none. Bonus starts at 5,000
and decreases by 15 per tick, with a minimum of zero. The sole winner receives
that bonus once; draws award none. Terminal states earn no further points.
Knockouts show a brief `BAA!` in the score slot instead of a pixel burst.
The footer shows round survival points above combined totals for each color,
with Energy and Bonus on the right. Large displayed scores use `k` abbreviations;
the stored values remain exact. The result announces the winner's bonus.
These rates are configurable with `points_per_tick`, `bonus_start`, and `bonus_decay`;
set the bonus start to zero to disable it.

`Config` fields: `width`, `height`, `step_ms`, `shrink_after`, `shrink_every`,
`warning_ticks`, `explosion_radius`, `retract_speed`, `points_per_tick`,
`bonus_start`, and `bonus_decay`. Initial contraction defaults to the number of boundary cells,
`2 * (width + height) - 4`; `shrink_after: :never` disables it. Each contraction
removes one outer ring before movement. A rider on that ring is swept away.
Warnings flash during the final eight ticks, then shrink every twenty ticks.
Board Energy displays remaining ticks until the next contraction and resets to
the contraction interval after each shrink. The final minimum arena stops shrinking.

Wikipedia confirms survival-based scoring and timed contraction; the screenshot
confirms colors, edge starts, and bottom scores/energy. The exact original energy
formula and draw behavior are unverified. The supplied screenshots support the score/bonus rates; our explicit rules above
are adaptation choices, not claims of exact emulation.

## AI and controllers

The badge page uses `SimpleBot`: it keeps going straight until a trail, wall,
oncoming head or dead end requires a turn, unless a nearby projected opponent
route presents an actual cutoff opportunity. It chooses the longer clear turning
lane when straight travel is unsafe. Short safety checks run every tick; full
lane scans run only on forced turns, without a board-wide flood fill. Seeded tie
breaking chooses between equal lanes. Each decision advances the seed, and the
same initial seed reproduces a match. Rematches, settings and B retain this policy.
Advanced presets below apply to headless `Match.demo`, not to badge play.

Every rider has a controller: `:human` or `{module, memory}`. Modules implement
`Controller.init/1` and `choose(game, player_id, memory) -> {turn_or_nil, memory}`.
All controllers see the same pre-step state, never opponents' queued commands.
Changing ownership clears pending human input.
`Match.demo/3` accepts `:human`, `:inactive`, built-in profile settings, or any
`{module, memory}` controller for each slot. For example:

```elixir
defmodule MyPilot do
  @behaviour Badge.App.Goatwars.Controller
  @impl true
  def init(seed), do: seed

  @impl true
  def choose(_game, _id, memory), do: {:left, memory + 1}
end

Match.demo(%{width: 78, height: 46}, 1, %{
  1 => {MyPilot, MyPilot.init(7)}, 2 => :human, 4 => :inactive
})
```

This intentionally simple sample is a working interface example, not a competitive
policy. Local controller code is trusted and runs synchronously; future external
entrants need isolated execution and deadline enforcement in the network runner.
Remote input already has a suitable adapter boundary: assign `:human`, submit an
accepted turn with `Match.command/3`, and advance once with `Match.tick/1`. No socket
or remote service is implemented yet. The game core knows nothing about
controller code. `Match.replay` records command maps newest first; reverse it and
feed `Game.step/2` to replay a match without running the AI again. Replay recording
is enabled by default for host runners; `Match.demo/4` and `Match.new/3` accept
`record_replay: false`. The badge page disables it, including after rematches.

`Bot.Profile` holds all tuning settings. Named presets are starting points for
playtesting, not established skill rankings:

| Preset | Think every (ticks) | Decision delay | Search cells | Aggression | Prediction ticks |
| --- | --- | --- | --- | --- | --- |
| beginner | 5 | 2 | 48 | 1 | 3 |
| intermediate | 3 | 1 | 160 | 4 | 6 |
| expert | 2 | 1 | 320 | 6 | 8 |
| pro | 1 | 0 | 640 | 8 | 10 |

At 100 ms per tick, intermediate thinks every 300 ms and acts after 100 ms.
It forecasts its own forward motion while waiting, evaluates reachable space and
runway, pursues projected opponent positions, and rewards interception lines.
It intentionally cannot rethink during its reaction interval. It is a bounded
heuristic, not a full adversarial search.

Additional knobs: `caution` (shared-destination penalty, default 12), `safe_room`
(space score cap, 24), `space_weight` (1), `runway_weight` (1), `runway_limit` (8),
and `tie_modulus` (11, seeded tie variation). `aggression: 0` disables pursuit.
All settings are validated integers; decision delay must be less than reaction
interval. Seeds are explicit, so headless and interactive decisions agree.

```elixir
alias Badge.App.Goatwars.{Bot, Match, Page}

Bot.init(42, :expert)
Bot.init(42, reaction_ticks: 4, decision_delay: 2, aggression: 7, caution: 10)

match = Match.demo(%{width: 78, height: 46}, 42, %{
  1 => :beginner,
  2 => :expert,
  3 => [reaction_ticks: 4, decision_delay: 2, aggression: 7],
  4 => :pro
})
result = Match.run(match, 78 * 46 * 5)

# Configurable badge shell with a human rider:
Page.init(rules: %{width: 78, height: 46, step_ms: 100}, profiles: %{1 => :human})
```

In the running simulator IEx, apply that page setup to the live demo:

```elixir
:sys.replace_state(Badge.UI, fn ui ->
  %{ui | page_state: Page.init(profiles: %{1 => :human, 4 => :inactive}), dirty: true}
end)
```

Use the fully qualified `Badge.App.Goatwars.Page` unless you first create the alias.
For future remote humans or externally written bots, add an authoritative runner
that turns authenticated, numbered commands into these same per-tick turns.
Transport, deadlines, snapshots, disconnects, and ownership belong outside `Game`.

## Verification and limitations

Tests cover collisions, plain-map state, contraction/warnings, deterministic replays,
input consumption, AI delay/pursuit/configuration, badge timing, scoring and rematches.
The browser loader registers the app only in the host runtime; firmware source
and store publishing are unchanged. Bitmap play uses one scaled image; legacy
map rendering compresses horizontal trail runs.

Readiness checks now run on the refactored GoatWars source: native badge-v1
AtomVM execution, actual released boot-library loading, pack/signature checks,
resource sweeps and real Store firmware UI integration. See
[the evidence report](../../docs/goatwars-readiness.md) for exact snapshots,
commands and limits. The selected Store firmware's HTTPS SSL crash risk remains
unresolved. Physical frame timing, display output and internal RAM must still be
measured. A fresh badge build needs the empty host-dependency directories that
`mix store.pack` prepares before `mix atomvm.check` can run.

Original references: [original game](https://en.wikipedia.org/wiki/BeamWars),
[screenshot and archive](https://www.macintoshrepository.org/3074-beamwars).
See [the build plan and reading guide](../../docs/tron-plan.md) for local examples.

Headless options include `--width`, `--height`, `--seed`, `--level`,
`--shrink-after`, `--shrink-every`, `--explosion-radius`, and `--retract-speed`.
For a quick contraction stress run:

```sh
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- elixir scripts/goatwars_headless.exs \
  --rounds 20 --level expert --shrink-after 12 --shrink-every 6
```

See [resource testing notes](../../docs/goatwars-resources.md) for the Snake hardware
report, measured rendering risks, native AtomVM heap caps and ESP32-S3 QEMU options.

## Offline USB installation

Use [the repeatable installer and device test steps](../../docs/goatwars-usb.md).
`./scripts/goatwars_install.sh --build-only` prepares images without a board;
`./scripts/goatwars_install.sh` builds and flashes the offline game.
