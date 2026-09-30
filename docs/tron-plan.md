# GoatWars build plan and reading guide

The functional core with typed maps, explosion clearing/retraction, configurable AI/controllers,
player setup, scoring/bonuses, headless runner and badge
browser demo are implemented. See [run instructions and tuning](../apps/goatwars/README.md).
The game was initially called GoaTRON; the current app ID and namespace are
`goatwars` and `Badge.App.Goatwars`.

## Read these first

1. [Badge README](../../avm_badge/README.md): board, simulator, host tests and flashing.
2. [Badge.Page](../../avm_badge/lib/badge/page.ex): callbacks and AtomGL drawing contract.
3. [Badge.UI](../../avm_badge/lib/badge/ui.ex): key dispatch, status/header, 100 ms tick.
4. [Sokoban engine](../apps/sokoban/lib/badge/app/sokoban/board.ex), [tests](../test/badge/app/sokoban/board_test.exs),
   [page](../apps/sokoban/lib/badge/app/sokoban/page.ex): another functional core plus badge adapter.
5. [Snake PR #1](https://github.com/mwingert/avm_badge_apps/pull/1), checked out at
   `.worktrees/snake-pr1`, commit `1048534`. Its `apps/snake/lib/game.ex`, `render.ex`
   and `page.ex` demonstrate autopilot space search and presentation separation.
   Snake's disappearing tail and food rules differ from permanent lightcycle trails.
6. [Fractals page](../apps/fractals/lib/badge/app/fractals/page.ex): worker lifecycle and stale results.

Simulator: [entry](../../avm_badge/sim/lib/badge/sim.ex),
[board](../../avm_badge/sim/lib/badge/sim/board.ex),
[keys](../../avm_badge/sim/lib/badge/sim/live.ex),
[fakes](../../avm_badge/sim/lib/badge/sim/fakes.ex).
The existing [smoke check](../../avm_badge/sim/lib/badge/sim/check.ex) does not
provide gameplay coverage for store apps. Two tabs share one simulated badge.

Networking candidates: [cluster link](../../avm_badge/lib/badge/cluster/link.ex),
[host example](../../avm_badge/tools/cluster.exs),
[WebSocket wrapper](../../avm_badge/lib/badge/chat/socket.ex).
These are transport examples, not an existing multiplayer match service.
[Keyboard implementation](../../avm_badge/lib/badge/keyboard.ex) documents repeat
and matrix constraints. Packaging lives in [the pack task](../lib/mix/tasks/store/pack.ex).

General references: [AtomVM programmer's guide](https://doc.atomvm.org/main/programmers-guide.html),
[AtomVM examples](https://github.com/atomvm/atomvm_examples),
[ExAtomVM](https://github.com/atomvm/ExAtomVM),
[ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html).
Prefer this firmware's actual fork over generic documentation for runtime support.

## Architecture

| Component | Responsibility |
| --- | --- |
| Config / Arena / Player / State maps | Explicit, validated game data |
| Game | Pure deterministic simultaneous steps and collision resolution |
| Controller / Bot.Profile / Bot | Input-source contract and tunable AI memory/policy |
| Match | Controller ownership, pending input, replay, survival scores and bonuses |
| Page.State / Page | Badge clock adapter, key bindings, rematches and total scores |
| Render.Layout / Render | Convert state into drawing items |

Maps index players, occupied coordinates and controller assignments; constructors return plain maps
for state records. Controllers, clocks, colors, keys and sockets stay outside
the game state. One owner resolves every player together; no process per bike.

## Next milestones

1. Tune AI profiles through headless tournaments and human play. Measure survival,
   draws and winner distribution across seeds, spawn rotations, and board sizes.
   Presets need playtesting before claiming beginner/expert strength.
2. Add an authoritative network match. Commands carry match ID, player ID, target
   tick and sequence. Authenticate ownership, reject stale/duplicate turns, bound
   buffering, and define timeout/disconnect behavior. Both independent clients must
   agree with the host result and replay under delayed or dropped messages.
3. Define a versioned public observation/command protocol for external entrants.
   Run entrants on hosts, with explicit time budgets and human takeover; do not
   load arbitrary entrant code into the badge. Keep transport out of `Game.step/2`.
4. Validate on the actual AtomVM runtime, align firmware Store support, then measure
   ESP32 heap, input latency, long trails, rendering and Wi-Fi on physical badges.
5. Integrate held keys only with keyup/focus-loss clearing or hardware held-label
   reconciliation. Single-tap input is sufficient today.

All software slices use TDD: failing test first, implementation, passing checks,
then a commit at a logical functionality boundary. No rule tests require real time.

## Runtime notes

Elixir analogs exist when the custom standard library implements them. Dropping
into Erlang is not a general escape hatch: the Erlang module or VM native function
must also exist. Verified in the badge-v1 fork: Enum.reverse and Enum.member? are
implemented, Map.from_struct is implemented, Enum.sort is absent, and lists sorting
is present. Native `nif_error` stubs alone do not establish missing functionality.
Current sorting uses `:lists` for that concrete gap. Browser and host tests remain
insufficient proof of deployability; the compatibility checker also has documented
false positives, so inspect new failures against the actual image.

Sources: [Enum](https://github.com/protolux-electronics/AtomVM/blob/badge-v1/libs/exavmlib/lib/Enum.ex),
[Map](https://github.com/protolux-electronics/AtomVM/blob/badge-v1/libs/exavmlib/lib/Map.ex),
[lists](https://github.com/protolux-electronics/AtomVM/blob/badge-v1/libs/estdlib/src/lists.erl),
[native functions](https://github.com/protolux-electronics/AtomVM/blob/badge-v1/src/libAtomVM/nifs.c).

Resource validation: [Snake hardware report, measurements and constrained-runtime options](goatwars-resources.md).
