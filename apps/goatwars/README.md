# GoatWars

A four-player lightcycle demo inspired by Steve Crutchfield's Macintosh lightcycle game.
The pure Elixir engine runs without a badge, display, network, clock, or processes.
The browser uses the real badge page API through the sibling firmware's simulator.

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
Visit http://localhost:3240. Four AI riders launch after a three-second countdown, scores accumulate,
and completed rounds restart after two seconds. Two browser tabs share one board.
Exit the simulator's IEx with Ctrl-C, then `a`.

| Keys | Action |
| --- | --- |
| Left / Right | Take over blue (player 1), turn left / right |
| A / D | Take over red (player 2) |
| J / L | Take over green (player 3) |
| V / N | Take over yellow (player 4) |
| Space | Pause / resume |
| R | New round, preserve total scores |
| S | Open / cancel player settings |
| B | Return all riders to default AI |
| Esc, then F1 | Home, then reopen GoatWars |

In settings, Up/Down selects a player; Left/Right cycles Human, AI Simple and
Inactive. C cycles left/right key presets; choosing
an occupied preset swaps assignments. R toggles beam retraction. Enter applies
settings and starts a new countdown. At least two slots must be active. Settings
suspend the match; S cancels without applying changes.

A keypress supplies one turn on the next tick; absent input maintains direction.
The last press before a tick wins. Held-key integration remains deferred.

## Rules and configuration

The badge preset is 78×46 cells at 100 ms per step. Blue starts at the bottom,
red at the top, green at the left and yellow at the right, facing inward.
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

The badge page uses `SimpleBot`: continue straight when clear, otherwise try
left and right once. It performs no search, prediction or pursuit. Rematches,
settings and B all retain this local policy. Advanced presets below apply to
headless `Match.demo`, not to badge play.

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
and store publishing are unchanged. The renderer compresses horizontal trail runs.

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
