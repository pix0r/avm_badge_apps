# BeamWars

A four-player lightcycle demo inspired by Steve Crutchfield's Macintosh BeamWars.
The pure Elixir engine runs without a badge, display, network, clock, or processes.
The browser uses the real badge page API through the sibling firmware's simulator.

## Run

From the apps repository, with Elixir 1.18.3 / OTP 27 installed through mise:

```sh
# No dependencies or simulator needed for these:
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- elixir scripts/beamwars_test.exs
mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- elixir scripts/beamwars_headless.exs --rounds 20

# Browser (requires ../avm_badge and its dependencies):
./scripts/beamwars_sim.sh
```

On first setup, run `MIX_TARGET=host mix deps.get` in `../avm_badge` with the same
mise toolchain. The script accepts `AVM_BADGE_PATH` for a different firmware path.
Visit http://localhost:3240. Four AI riders start automatically, scores accumulate,
and completed rounds restart after two seconds. Two browser tabs share one board.
Exit the simulator's IEx with Ctrl-C, then `a`.

| Keys | Action |
| --- | --- |
| Left / Right | Take over blue (player 1), turn left / right |
| A / D | Take over red (player 2) |
| J / L | Take over green (player 3) |
| V / N | Take over yellow (player 4) |
| Space | Pause / resume |
| R | New round, preserve scores |
| B | Return all riders to default AI |
| Esc, then F1 | Home, then reopen BeamWars |

A keypress supplies one turn on the next tick; absent input maintains direction.
The last press before a tick wins. Held-key integration remains deferred.

## Rules and configuration

The badge preset is 78×46 cells at 100 ms per step. Blue starts at the bottom,
red at the top, green at the left and yellow at the right, facing inward.
The core accepts arbitrary rosters of two or more players through `Game.new/2`;
`Match.demo/3` supplies four edge spawns and requires dimensions at least 2×2.

All movement is simultaneous. Own trails, opponents' trails, old heads, walls,
and shared destinations kill a rider. Trails persist after death. The last rider
wins; simultaneous elimination of the last riders is a draw. Each successful
surviving step earns one point. A crashing step earns none. Terminal states earn
no more points. The demo totals survival points across rematches, with no win bonus.

`Config` fields: `width`, `height`, `step_ms`, `shrink_after`, `shrink_every`,
`warning_ticks`. Initial contraction defaults to the number of boundary cells,
`2 * (width + height) - 4`; `shrink_after: :never` disables it. Each contraction
removes one outer ring before movement. A rider on that ring is swept away.
Warnings flash during the final eight ticks, then shrink every twenty ticks.
Board Energy displays remaining ticks until the next contraction and resets to
the contraction interval after each shrink. The final minimum arena stops shrinking.

Wikipedia confirms survival-based scoring and timed contraction; the screenshot
confirms colors, edge starts, and bottom scores/energy. The exact original energy
formula and draw behavior are unverified. Our explicit rules above are adaptation
choices, not claims of exact emulation.

## AI and controllers

Every rider has a controller: `:human` or `{module, memory}`. Modules implement
`Controller.init/1` and `choose(game, player_id, memory) -> {turn_or_nil, memory}`.
All controllers see the same pre-step state, never opponents' queued commands.
Changing ownership clears pending human input. The game core knows nothing about
controller code. `Match.replay` records command maps newest first; reverse it and
feed `Game.step/2` to replay a match without running the AI again.

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
alias Badge.App.Beamwars.{Bot, Match, Page}

Bot.init(42, :expert)
Bot.init(42, reaction_ticks: 4, decision_delay: 2, aggression: 7, caution: 10)

match = Match.demo(%{width: 78, height: 46}, 42, %{
  1 => :beginner,
  2 => :expert,
  3 => [reaction_ticks: 4, decision_delay: 2, aggression: 7],
  4 => :pro
})
result = Match.run(match, 78 * 46)

# Configurable badge shell; AI profiles survive rematches:
Page.init(rules: %{width: 78, height: 46, step_ms: 100}, profiles: %{1 => :expert})
```

In the running simulator IEx, apply that page setup to the live demo:

```elixir
:sys.replace_state(Badge.UI, fn ui ->
  %{ui | page_state: Page.init(profiles: %{1 => :beginner, 2 => :expert}), dirty: true}
end)
```

Use the fully qualified `Badge.App.Beamwars.Page` unless you first create the alias.
For future remote humans or externally written bots, add an authoritative runner
that turns authenticated, numbered commands into these same per-tick turns.
Transport, deadlines, snapshots, disconnects, and ownership belong outside `Game`.

## Verification and limitations

Tests cover collisions, typed state, contraction/warnings, deterministic replays,
input consumption, AI delay/pursuit/configuration, badge timing, scoring and rematches.
The browser loader registers the app only in the host runtime; firmware source
and store publishing are unchanged. The renderer compresses horizontal trail runs.

Host verification does not prove AtomVM instruction compatibility, ESP32 memory
usage, display performance, or radio behavior. The real badge UI ticks every 100 ms,
so faster requested movement rates cannot be achieved by changing `step_ms` alone.
Network play and hardware validation are the next milestones. Current full-project
pack tests require `Badge.Store`, missing from this sibling checkout; align firmware
versions before packaging or publishing.

Original references: [BeamWars](https://en.wikipedia.org/wiki/BeamWars),
[screenshot and archive](https://www.macintoshrepository.org/3074-beamwars).
See [the build plan and reading guide](../../docs/tron-plan.md) for local examples.
