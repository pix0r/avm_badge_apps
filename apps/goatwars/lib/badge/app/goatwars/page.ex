defmodule Badge.App.Goatwars.Page do
  @moduledoc """
  GoatWars badge adapter. S opens player settings; Space pauses; R rematches.

  Steering is buffered in the UI; game steps finish through an app-owned worker.
  """
  use Badge.Page
  alias Badge.App.Goatwars.{Art, Game, Match, Render, Setup, SimpleBot}
  alias __MODULE__.State

  @impl true
  def title, do: "GoatWars"
  @impl true
  def icon, do: :cross
  @impl true
  def init(options \\ []) do
    loading = Keyword.get(options, :loading, Keyword.get(options, :countdown_ms, 3000) != 0)
    if loading, do: %{screen: :loading, startup: :paint, options: options}, else: prepare(options)
  end

  defp prepare(options) do
    rules =
      Keyword.get(options, :rules, %{width: 23, height: 23, step_ms: 200, explosion_radius: 2, retract_speed: 8})

    setup = Setup.new(Keyword.get(options, :profiles, %{}))
    seed = Keyword.get(options, :seed, 1)
    %{game: %{config: config} = game} = match = Match.demo(rules, seed, controllers(setup, seed), record_replay: false)
    compact = Keyword.get(options, :compact, true)
    match = if compact, do: %{match | game: Game.compact(game)}, else: match
    %{width: width, height: height, retract_speed: retract_speed, step_ms: step_ms} = config

    setup = %{
      setup
      | retract: retract_speed > 0,
        board: {width, height},
        step_ms: step_ms
    }

    countdown = Keyword.get(options, :countdown_ms, 3000)

    State.new(%{
      match: match,
      compact: compact,
      layout: Render.layout(config),
      setup: setup,
      art: Art.load(),
      screen: if(countdown == 0, do: :game, else: :title),
      started: countdown == 0,
      launch_remaining: countdown
    })
  end

  @impl true
  def handle_key(_event, %{screen: :loading}), do: :ignore
  def handle_key(event, %{screen: :settings} = state), do: settings_key(event, state)
  def handle_key(event, %{screen: :title} = state), do: title_key(event, state)

  def handle_key({:char, ?t}, state),
    do: {:ok, %{state | benchmark: not Map.fetch!(state, :benchmark), bench_previous: nil}}

  def handle_key({:char, ?m}, %{benchmark: true} = state),
    do: {:ok, restart(%{state | compact: not Map.fetch!(state, :compact), bench_previous: nil, scores: %{}, round: 0})}

  def handle_key({:char, ?s}, state), do: open_settings(state)

  def handle_key({:char, 32}, state) do
    leave(state)
    {:ok, %{state | paused: not Map.fetch!(state, :paused), due_at: nil, launch_at: nil}}
  end

  def handle_key({:char, char}, state) when char == ?r or char == ?R, do: {:ok, restart(state)}

  def handle_key({:char, char}, state) when char == ?b or char == ?B do
    leave(state)
    match =
      Enum.reduce(Map.keys(Map.fetch!(Map.fetch!(state, :match), :controllers)), Map.fetch!(state, :match), fn id, match ->
        Match.control(match, id, {SimpleBot, SimpleBot.init(Map.fetch!(state, :round) * 31 + id * 13)})
      end)

    setup =
      Enum.reduce(Map.keys(Map.fetch!(match, :controllers)), Map.fetch!(state, :setup), &Setup.mode(&2, &1, :intermediate))

    {:ok, %{state | match: match, setup: setup}}
  end

  def handle_key(event, %{input_ref: ref, setup: setup}) do
    case Setup.binding(setup, event) do
      {id, turn} ->
        turns =
          case :erlang.get(ref) do
            :undefined -> %{}
            turns -> turns
          end

        :erlang.put(ref, Map.put(turns, id, turn))
        :ignore

      nil ->
        :ignore
    end
  end

  @impl true
  def leave(%{input_ref: ref}) do
    :erlang.erase(ref)
    case :erlang.erase({:goatwars_work, ref}) do
      {worker, monitor} ->
        :erlang.exit(worker, :kill)
        :erlang.demonitor(monitor, [:flush])
      :undefined -> :ok
    end
    :ok
  end
  def leave(_state), do: :ok

  defp apply_turns([], state), do: state

  defp apply_turns([{id, turn} | rest], %{match: match, setup: setup} = state) do
    match = match |> Match.control(id, :human) |> Match.command(id, turn)
    apply_turns(rest, %{state | match: match, setup: Setup.mode(setup, id, :human)})
  end

  defp title_key(:enter, state), do: {:ok, %{state | screen: :game}}
  defp title_key({:edit, :newline}, state), do: title_key(:enter, state)
  defp title_key({:char, 13}, state), do: title_key(:enter, state)
  defp title_key({:char, ?s}, state), do: open_settings(state)
  defp title_key(_, _), do: :ignore

  defp open_settings(state) do
    leave(state)
    {:ok, %{state | screen: :settings, settings_from: Map.fetch!(state, :screen), draft: Map.fetch!(state, :setup)}}
  end

  defp settings_key({:move, :up}, state),
    do: {:ok, %{state | selected: max(Map.fetch!(state, :selected) - 1, 1)}}

  defp settings_key({:move, :down}, state),
    do: {:ok, %{state | selected: min(Map.fetch!(state, :selected) + 1, 4)}}

  defp settings_key({:move, turn}, state) when turn == :left or turn == :right do
    delta = if turn == :left, do: -1, else: 1

    {:ok,
     %{state | draft: Setup.cycle_mode(Map.fetch!(state, :draft), Map.fetch!(state, :selected), delta, [:human, :intermediate, :inactive])}}
  end

  defp settings_key({:char, ?c}, state),
    do: {:ok, %{state | draft: Setup.cycle_keys(Map.fetch!(state, :draft), Map.fetch!(state, :selected))}}

  defp settings_key({:char, ?r}, state),
    do: {:ok, %{state | draft: %{Map.fetch!(state, :draft) | retract: not Map.fetch!(Map.fetch!(state, :draft), :retract)}}}

  defp settings_key({:char, ?g}, state),
    do: {:ok, %{state | draft: Setup.cycle_board(Map.fetch!(state, :draft))}}

  defp settings_key({:char, ?a}, state),
    do: {:ok, %{state | draft: Setup.toggle_aspect(Map.fetch!(state, :draft))}}

  defp settings_key({:char, ?f}, state),
    do: {:ok, %{state | draft: Setup.adjust_speed(Map.fetch!(state, :draft), 10)}}

  defp settings_key({:char, ?v}, state),
    do: {:ok, %{state | draft: Setup.adjust_speed(Map.fetch!(state, :draft), -10)}}

  defp settings_key({:char, ?s}, state),
    do: {:ok, %{state | screen: Map.fetch!(state, :settings_from), draft: nil, launch_at: nil, due_at: nil}}

  defp settings_key(:enter, state) do
    if Setup.valid?(Map.fetch!(state, :draft)),
      do: {:ok, restart(%{state | setup: Map.fetch!(state, :draft), screen: :game, draft: nil})},
      else: {:ok, state}
  end

  defp settings_key({:edit, :newline}, state), do: settings_key(:enter, state)
  defp settings_key({:char, 13}, state), do: settings_key(:enter, state)
  defp settings_key(_, _), do: :ignore

  @impl true
  def tick(state), do: badge_advance(state, :erlang.monotonic_time(:millisecond))

  defp badge_advance(%{screen: :game, started: false, paused: false} = state, now) do
    state = launch(state, now)
    if Map.fetch!(state, :launch_remaining) == 0, do: badge_advance(%{state | started: true}, now), else: state
  end

  defp badge_advance(%{screen: :game, started: true, paused: false, result_until: nil, due_at: due, input_ref: ref} = state, now)
       when due == nil or now >= due do
    case :erlang.get({:goatwars_work, ref}) do
      :undefined ->
        parent = self()
        turns = :erlang.erase(ref)
        options = if :erlang.system_info(:machine) == ~c"BEAM", do: [:monitor], else: [:monitor, {:atomvm_heap_growth, :fibonacci}]
        job = :erlang.spawn_opt(fn ->
          if turns != :undefined, do: :erlang.put(ref, turns)
          started = :erlang.monotonic_time(:microsecond)
          next = advance(state, now)
          elapsed = :erlang.monotonic_time(:microsecond) - started
          send(parent, {:goatwars_step, ref, self(), next, elapsed})
        end, options)
        :erlang.put({:goatwars_work, ref}, job)
        state
      _running -> state
    end
  end

  defp badge_advance(state, now), do: advance(state, now)

  @impl true
  def handle_info({:goatwars_step, ref, worker, next, elapsed}, %{input_ref: ref} = state) do
    case :erlang.get({:goatwars_work, ref}) do
      {^worker, monitor} ->
        :erlang.erase({:goatwars_work, ref})
        :erlang.demonitor(monitor, [:flush])
        {:ok, measured_step(state, next, elapsed)}
      _stale -> :ignore
    end
  end

  def handle_info({:DOWN, monitor, :process, worker, reason}, %{input_ref: ref}) when reason != :normal do
    case :erlang.get({:goatwars_work, ref}) do
      {^worker, ^monitor} ->
        :erlang.erase({:goatwars_work, ref})
        :erlang.error(reason)
      _stale -> :ignore
    end
  end

  def handle_info(_message, _state), do: :ignore

  defp measured_step(%{benchmark: false}, next, _elapsed), do: %{next | benchmark: false, bench_previous: nil}

  defp measured_step(%{bench_previous: previous}, next, elapsed) do
    now = :erlang.monotonic_time(:microsecond)
    if previous != nil and checkpoint?(next) do
      :io.format(~c"GW_DEVICE mode=~s tick=~p phase=tick cpu_us=~p frame_gap_us=~p~n",
        [mode(next), round_tick(next), elapsed, now - previous])
    end
    %{next | benchmark: true, bench_previous: now}
  end

  @impl true
  def refresh(%{screen: :loading}), do: 0
  def refresh(state), do: min(tick_interval(state), 100)

  def tick_interval(%{screen: :game, started: true, paused: false, result_until: nil, match: %{game: %{config: %{step_ms: ms}}}}),
    do: ms

  def tick_interval(_state), do: 100

  @doc "Advances against an explicit clock for deterministic shell tests."
  def advance(%{screen: :loading, startup: :paint} = state, _now), do: %{state | startup: :prepare}
  def advance(%{screen: :loading, startup: :prepare, options: options}, _now), do: prepare(options)
  def advance(%{screen: :settings} = state, _now), do: state
  def advance(%{screen: :title} = state, _now), do: state
  def advance(%{paused: true} = state, _now), do: state

  def advance(%{started: false} = state, now) do
    state = launch(state, now)
    if Map.fetch!(state, :launch_remaining) == 0, do: advance(%{state | started: true}, now), else: state
  end

  def advance(%{result_until: deadline} = state, now) when is_integer(deadline) do
    if now >= deadline do
      restart(state)
    else
      match = %{Map.fetch!(state, :match) | game: Game.cleanup(Map.fetch!(Map.fetch!(state, :match), :game))}
      %{state | match: match, effects: age_effects(Map.fetch!(state, :effects)), frame: Map.fetch!(state, :frame) + 1}
    end
  end

  def advance(state, now) when is_integer(state.due_at) and now < state.due_at, do: state

  def advance(
        %{
          input_ref: ref,
          match: %{totals: previous_totals},
          scores: previous_scores,
          effects: previous_effects,
          due_at: previous_due,
          frame: frame
        } = state,
        now
      ) do
    %{match: previous_match} = state =
      case :erlang.erase(ref) do
        :undefined -> state
        turns -> apply_turns(:maps.to_list(turns), state)
      end
    %{totals: totals, events: events, game: %{config: %{step_ms: step_ms}, status: status}} = match = Match.tick(previous_match)
    scores = add_scores(:maps.to_list(totals), previous_totals, previous_scores)
    effects = crash_effects(events, age_effects(previous_effects))
    due_at = if is_integer(previous_due) and now < previous_due + step_ms * 2, do: previous_due + step_ms, else: now + step_ms

    %{
      state
      | scores: scores,
        match: match,
        due_at: due_at,
        effects: effects,
        frame: frame + 1,
        result_until: if(status == :running, do: nil, else: now + 2000)
    }
  end

  defp crash_effects([], effects), do: effects

  defp crash_effects([{:crashed, id, position} | rest], effects),
    do: [Render.Explosion.new(id, position) | crash_effects(rest, effects)]

  defp crash_effects([_ | rest], effects), do: crash_effects(rest, effects)

  defp add_scores([], _previous, scores), do: scores

  defp add_scores([{id, total} | rest], previous, scores) do
    gain = total - score(previous, id)
    scores = if gain == 0, do: scores, else: Map.put(scores, id, score(scores, id) + gain)
    add_scores(rest, previous, scores)
  end

  defp age_effects([]), do: []

  defp age_effects([%{age: age} = effect | rest]) when age < 5,
    do: [%{effect | age: age + 1} | age_effects(rest)]

  defp age_effects([_ | rest]), do: age_effects(rest)

  defp launch(state, now) do
    deadline = Map.fetch!(state, :launch_at) || now + Map.fetch!(state, :launch_remaining)
    %{state | launch_at: deadline, launch_remaining: max(deadline - now, 0), frame: Map.fetch!(state, :frame) + 1}
  end

  defp restart(
         %{
           setup: %{board: {width, height}, step_ms: step_ms, retract: retract} = setup,
           match: %{game: %{config: previous}},
           round: round,
           compact: compact
         } = state
       ) do
    leave(state)
    %{width: old_width, height: old_height, shrink_after: old_shrink, retract_speed: old_retract} = previous
    shrink_after = if {width, height} == {old_width, old_height}, do: old_shrink, else: 2 * (width + height) - 4

    config = %{
      previous
      | width: width,
        height: height,
        step_ms: step_ms,
        shrink_after: shrink_after,
        retract_speed: if(retract, do: if(old_retract > 0, do: old_retract, else: 8), else: 0)
    }

    seed = round + 1
    %{game: game} = match = Match.demo(config, seed, controllers(setup, seed), record_replay: false)
    match = if compact, do: %{match | game: Game.compact(game)}, else: match

    %{
      state
      | match: match,
        layout: Render.layout(config),
        round: seed,
        result_until: nil,
        due_at: nil,
        started: false,
        launch_at: nil,
        launch_remaining: 3000,
        effects: [],
        paused: false
    }
  end

  defp controllers(setup, seed) do
    setup
    |> Setup.controllers()
    |> Enum.map(fn
      {id, mode} when mode == :human or mode == :inactive -> {id, mode}
      {id, mode} -> {id, {SimpleBot, SimpleBot.init(seed * 31 + id * 13, mode)}}
    end)
    |> Map.new()
  end

  @impl true
  def render(%{screen: :loading}) do
    [
      {:text, 88, 100, :default16px, 0xFFF5CC, 0x241332, "Loading GoatWars..."},
      {:text, 84, 124, :default16px, 0x5DE2B4, 0x241332, "Warming up the herd"},
      {:rect, 0, 24, 320, 216, 0x241332}
    ]
  end

  def render(%{screen: :settings} = state), do: render_settings(state)
  def render(%{screen: :title, art: art}), do: Render.Interstitial.title(art)

  def render(%{benchmark: true} = state) do
    started = :erlang.monotonic_time(:microsecond)
    items = render_game(state)
    elapsed = :erlang.monotonic_time(:microsecond) - started

    if checkpoint?(state) do
      :io.format(
        ~c"GW_DEVICE mode=~s tick=~p phase=render cpu_us=~p heap=~p queue=~p~n",
        [
          mode(state),
          round_tick(state),
          elapsed,
          :erlang.process_info(self(), :heap_size),
          :erlang.process_info(self(), :message_queue_len)
        ]
      )
    end

    items
  end

  def render(state), do: render_game(state)

  defp mode(%{compact: true}), do: ~c"bitmap"
  defp mode(_), do: ~c"legacy"
  defp round_tick(state), do: Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :tick)

  defp checkpoint?(state) do
    tick = round_tick(state)
    Map.fetch!(state, :started) and (tick == 97 or (tick > 0 and rem(tick, 10) == 0))
  end

  defp render_game(
         %{started: false, paused: false, launch_remaining: remaining, match: %{game: game}, layout: layout, frame: frame} = state
       ) do
    [
      {:text, 156, 108, :default16px, 0xFFFFFF, 0x241332, int(div(remaining + 999, 1000))},
      {:rect, 144, 102, 32, 28, 0x241332}
    ] ++ Render.cannons(game, layout) ++ hud(state) ++ Render.scene(game, layout, frame)
  end

  defp render_game(%{match: %{game: game}, layout: layout, frame: frame, art: art} = state) do
    case caption(state) do
      nil ->
        hud(state) ++
          Render.scene(game, layout, frame)

      {title, hint, color} ->
        Render.Interstitial.scene(art, title, hint, color) ++ hud(state)
    end
  end

  defp hud(%{
         match: %{game: %{arena: %{next_shrink_tick: deadline}, tick: tick}, scores: scores, bonus: bonus},
         scores: totals,
         effects: effects
       }) do
    energy = if deadline == nil, do: 0, else: max(deadline - tick, 0)

    tail = [
      {:text, 180, 210, :default16px, 0xFFFFFF, 0x241332, "Energy"},
      {:text, 180, 224, :default16px, 0xFFFFFF, 0x241332, int(energy)},
      {:text, 256, 210, :default16px, 0xFFFFFF, 0x241332, "Bonus"},
      {:text, 256, 224, :default16px, 0xFFFFFF, 0x241332, int(bonus)},
      {:rect, 0, 209, 320, 31, 0x241332}
    ]

    hud_scores(1, 4, scores, totals, effects, tail)
  end

  defp hud_scores(5, _x, _scores, _totals, _effects, tail), do: tail

  defp hud_scores(id, x, scores, totals, effects, tail) do
    label = if knocked_out?(effects, id), do: "BAA!", else: short(score(scores, id))

    [
      {:text, x, 210, :default16px, 0xFFFFFF, 0x241332, label},
      {:text, x, 224, :default16px, 0xFFFFFF, 0x241332, short(score(totals, id))},
      {:rect, x, 209, 36, 1, Render.color(id)}
      | hud_scores(id + 1, x + 43, scores, totals, effects, tail)
    ]
  end

  defp score(scores, id) do
    case scores do
      %{^id => value} -> value
      _ -> 0
    end
  end

  defp knocked_out?([], _id), do: false
  defp knocked_out?([%{id: id} | _], id), do: true
  defp knocked_out?([_ | rest], id), do: knocked_out?(rest, id)

  defp caption(%{paused: true}), do: {"PAUSED", "Space: back to the herd", 0xFFFFFF}

  defp caption(%{match: %{game: %{status: :draw}}}), do: {"DRAW", "No goat left standing", 0xFFFFFF}

  defp caption(%{match: %{awarded_bonus: {id, bonus}}}),
    do: {"PLAYER " <> int(id) <> " WINS", "BONUS " <> int(bonus), Render.color(id)}

  defp caption(_), do: nil

  defp render_settings(state) do
    setup = Map.fetch!(state, :draft)

    rows =
      Enum.flat_map(1..4, fn id ->
        slot = Map.fetch!(setup, :slots)[id]
        marker = if id == Map.fetch!(state, :selected), do: ">", else: " "

        text(8, 53 + (id - 1) * 22, marker <> "P" <> int(id), 0x241332) ++
          text(48, 53 + (id - 1) * 22, mode_label(Map.fetch!(slot, :mode)), 0xFFFFFF) ++
          text(268, 53 + (id - 1) * 22, Setup.key_label(Map.fetch!(slot, :keys)), 0xFFFFFF) ++
          [{:rect, 8, 51 + (id - 1) * 22, 32, 20, Render.color(id)}]
      end)

    hint = if Setup.valid?(setup), do: "Enter: start  S: cancel", else: "Need 2 active players"

    {width, height} = Map.fetch!(setup, :board)

    text(8, 29, "PLAYER SETTINGS", 0xFFFFFF) ++
      rows ++
      text(8, 144, "R: Retract " <> if(Map.fetch!(setup, :retract), do: "ON", else: "OFF"), 0xFFFFFF) ++
      text(176, 144, "A: " <> if(width == height, do: "Square", else: "Wide"), 0xFFFFFF) ++
      text(8, 162, "G: Board " <> Setup.board_label({width, height}) <> " " <> int(width) <> "x" <> int(height), 0xFFFFFF) ++
      text(8, 180, "F/V: Step " <> int(Map.fetch!(setup, :step_ms)) <> "ms", 0xFFFFFF) ++
      text(8, 198, "Arrows: mode  C: keys", 0xA4B8C9) ++
      text(8, 217, hint, 0xFFFFFF) ++
      [{:rect, 0, 24, 320, 216, 0x241332}]
  end

  defp mode_label(:human), do: "Human"
  defp mode_label(:inactive), do: "Inactive"
  defp mode_label(_), do: "AI Simple"

  defp text(x, y, label, color), do: [{:text, x, y, :default16px, color, :transparent, label}]
  defp int(number), do: :erlang.integer_to_binary(number)
  defp short(number) when number >= 10000, do: int(div(number, 1000)) <> "k"
  defp short(number), do: int(number)
end
