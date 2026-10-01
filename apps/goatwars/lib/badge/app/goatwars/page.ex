defmodule Badge.App.Goatwars.Page do
  @moduledoc "GoatWars badge adapter. S opens player settings; Space pauses; R rematches."
  use Badge.Page
  alias Badge.App.Goatwars.{Game, Match, Render, Setup, SimpleBot}
  alias __MODULE__.State

  @impl true
  def title, do: "GoatWars"
  @impl true
  def icon, do: :cross
  @impl true
  def init(options \\ []) do
    rules =
      Keyword.get(options, :rules, %{width: 51, height: 30, explosion_radius: 2, retract_speed: 8})

    setup = Setup.new(Keyword.get(options, :profiles, %{}))
    seed = Keyword.get(options, :seed, 1)
    match = Match.demo(rules, seed, controllers(setup, seed), record_replay: false)
    match = if Keyword.get(options, :compact, true), do: %{match | game: Game.compact(Map.fetch!(match, :game))}, else: match
    config = Map.fetch!(Map.fetch!(match, :game), :config)

    setup = %{
      setup
      | retract: Map.fetch!(config, :retract_speed) > 0,
        board: {Map.fetch!(config, :width), Map.fetch!(config, :height)},
        step_ms: Map.fetch!(config, :step_ms)
    }

    countdown = Keyword.get(options, :countdown_ms, 3000)

    State.new(%{
      match: match,
      compact: Keyword.get(options, :compact, true),
      layout: Render.layout(Map.fetch!(Map.fetch!(match, :game), :config)),
      setup: setup,
      started: countdown == 0,
      launch_remaining: countdown
    })
  end

  @impl true
  def handle_key(event, %{screen: :settings} = state), do: settings_key(event, state)

  def handle_key({:char, ?t}, state),
    do: {:ok, %{state | benchmark: not Map.fetch!(state, :benchmark), bench_previous: nil}}

  def handle_key({:char, ?m}, %{benchmark: true} = state),
    do: {:ok, restart(%{state | compact: not Map.fetch!(state, :compact), bench_previous: nil, scores: %{}, round: 0})}

  def handle_key({:char, ?s}, state), do: {:ok, %{state | screen: :settings, draft: Map.fetch!(state, :setup)}}

  def handle_key({:char, 32}, state),
    do: {:ok, %{state | paused: not Map.fetch!(state, :paused), due_at: nil, launch_at: nil}}

  def handle_key({:char, char}, state) when char == ?r or char == ?R, do: {:ok, restart(state)}

  def handle_key({:char, char}, state) when char == ?b or char == ?B do
    match =
      Enum.reduce(Map.keys(Map.fetch!(Map.fetch!(state, :match), :controllers)), Map.fetch!(state, :match), fn id, match ->
        Match.control(match, id, {SimpleBot, SimpleBot.init(Map.fetch!(state, :round) * 31 + id * 13)})
      end)

    setup =
      Enum.reduce(Map.keys(Map.fetch!(match, :controllers)), Map.fetch!(state, :setup), &Setup.mode(&2, &1, :intermediate))

    {:ok, %{state | match: match, setup: setup}}
  end

  def handle_key(event, state) do
    case Setup.binding(Map.fetch!(state, :setup), event) do
      {id, turn} ->
        match = Map.fetch!(state, :match) |> Match.control(id, :human) |> Match.command(id, turn)
        {:ok, %{state | match: match, setup: Setup.mode(Map.fetch!(state, :setup), id, :human)}}

      nil ->
        :ignore
    end
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

  defp settings_key({:char, ?f}, state),
    do: {:ok, %{state | draft: Setup.adjust_speed(Map.fetch!(state, :draft), 10)}}

  defp settings_key({:char, ?v}, state),
    do: {:ok, %{state | draft: Setup.adjust_speed(Map.fetch!(state, :draft), -10)}}

  defp settings_key({:char, ?s}, state),
    do: {:ok, %{state | screen: :game, draft: nil, launch_at: nil, due_at: nil}}

  defp settings_key(:enter, state) do
    if Setup.valid?(Map.fetch!(state, :draft)),
      do: {:ok, restart(%{state | setup: Map.fetch!(state, :draft), screen: :game, draft: nil})},
      else: {:ok, state}
  end

  defp settings_key({:edit, :newline}, state), do: settings_key(:enter, state)
  defp settings_key({:char, 13}, state), do: settings_key(:enter, state)
  defp settings_key(_, _), do: :ignore

  @impl true
  def tick(%{benchmark: true} = state) do
    started = :erlang.monotonic_time(:microsecond)
    next = advance(state, :erlang.monotonic_time(:millisecond))
    elapsed = :erlang.monotonic_time(:microsecond) - started
    previous = Map.fetch!(state, :bench_previous)

    if previous != nil and checkpoint?(next) do
      :io.format(
        ~c"GW_DEVICE mode=~s tick=~p phase=tick cpu_us=~p frame_gap_us=~p~n",
        [mode(next), round_tick(next), elapsed, started - previous]
      )
    end

    %{next | bench_previous: started}
  end

  def tick(state), do: advance(state, :erlang.monotonic_time(:millisecond))
  @impl true
  def refresh(state), do: tick_interval(state)

  @impl true
  def tick_interval(%{screen: :game, started: true, paused: false, result_until: nil, match: %{game: %{config: %{step_ms: ms}}}}),
    do: ms

  def tick_interval(_state), do: 100

  @doc "Advances against an explicit clock for deterministic shell tests."
  def advance(%{screen: :settings} = state, _now), do: state
  def advance(%{paused: true} = state, _now), do: state

  def advance(%{started: false} = state, now) do
    deadline = Map.fetch!(state, :launch_at) || now + Map.fetch!(state, :launch_remaining)
    remaining = max(deadline - now, 0)
    state = %{state | launch_at: deadline, launch_remaining: remaining, frame: Map.fetch!(state, :frame) + 1}
    if remaining == 0, do: advance(%{state | started: true}, now), else: state
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

  def advance(state, now) do
    match = Match.tick(Map.fetch!(state, :match))

    scores =
      add_scores(:maps.to_list(Map.fetch!(match, :totals)), Map.fetch!(Map.fetch!(state, :match), :totals), Map.fetch!(state, :scores))

    effects = crash_effects(Map.fetch!(match, :events), age_effects(Map.fetch!(state, :effects)))
    game = Map.fetch!(match, :game)
    step_ms = Map.fetch!(Map.fetch!(game, :config), :step_ms)
    previous_due = Map.fetch!(state, :due_at)
    due_at = if is_integer(previous_due) and now < previous_due + step_ms * 2, do: previous_due + step_ms, else: now + step_ms

    %{
      state
      | scores: scores,
        match: match,
        due_at: due_at,
        effects: effects,
        frame: Map.fetch!(state, :frame) + 1,
        result_until: if(Map.fetch!(game, :status) == :running, do: nil, else: now + 2000)
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

  defp restart(%{setup: %{board: {width, height}}} = state) do
    previous = Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :config)

    shrink_after =
      if {width, height} == {Map.fetch!(previous, :width), Map.fetch!(previous, :height)},
        do: Map.fetch!(previous, :shrink_after),
        else: 2 * (width + height) - 4

    config = %{
      Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :config)
      | width: width,
        height: height,
        step_ms: Map.fetch!(Map.fetch!(state, :setup), :step_ms),
        shrink_after: shrink_after,
        retract_speed:
          if(Map.fetch!(Map.fetch!(state, :setup), :retract),
            do:
              if(Map.fetch!(Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :config), :retract_speed) > 0,
                do: Map.fetch!(Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :config), :retract_speed),
                else: 8
              ),
            else: 0
          )
    }

    seed = Map.fetch!(state, :round) + 1
    match = Match.demo(config, seed, controllers(Map.fetch!(state, :setup), seed), record_replay: false)
    match = if Map.fetch!(state, :compact), do: %{match | game: Game.compact(Map.fetch!(match, :game))}, else: match

    %{
      state
      | match: match,
        layout: Render.layout(Map.fetch!(Map.fetch!(match, :game), :config)),
        round: Map.fetch!(state, :round) + 1,
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
  def render(%{screen: :settings} = state), do: render_settings(state)

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

  defp render_game(state) do
    overlay(state) ++
      hud(state) ++
      cannons(state) ++ Render.scene(Map.fetch!(Map.fetch!(state, :match), :game), Map.fetch!(state, :layout), Map.fetch!(state, :frame))
  end

  defp cannons(%{started: false} = state), do: Render.cannons(Map.fetch!(Map.fetch!(state, :match), :game), Map.fetch!(state, :layout))
  defp cannons(_), do: []

  defp hud(%{
         match: %{game: %{arena: %{next_shrink_tick: deadline}, tick: tick}, scores: scores, bonus: bonus},
         scores: totals,
         effects: effects
       }) do
    energy = if deadline == nil, do: 0, else: max(deadline - tick, 0)

    tail = [
      {:text, 180, 210, :default16px, 0xFFFFFF, 0x000020, "Energy"},
      {:text, 180, 224, :default16px, 0xFFFFFF, 0x000020, int(energy)},
      {:text, 256, 210, :default16px, 0xFFFFFF, 0x000020, "Bonus"},
      {:text, 256, 224, :default16px, 0xFFFFFF, 0x000020, int(bonus)},
      {:rect, 0, 209, 320, 31, 0x000020}
    ]

    hud_scores(1, 4, scores, totals, effects, tail)
  end

  defp hud_scores(5, _x, _scores, _totals, _effects, tail), do: tail

  defp hud_scores(id, x, scores, totals, effects, tail) do
    label = if knocked_out?(effects, id), do: "BAA!", else: short(score(scores, id))

    [
      {:text, x, 210, :default16px, 0xFFFFFF, 0x000020, label},
      {:text, x, 224, :default16px, 0xFFFFFF, 0x000020, short(score(totals, id))},
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

  defp overlay(%{paused: true}), do: panel("PAUSED", "Space to resume", 0xFFFFFF)

  defp overlay(%{started: false, launch_remaining: remaining}),
    do: panel(int(div(remaining + 999, 1000)), "READY", 0xFFFFFF)

  defp overlay(%{match: %{game: %{status: :draw}}}), do: panel("DRAW", "No bonus", 0xFFFFFF)

  defp overlay(%{match: %{awarded_bonus: {id, bonus}}}),
    do: panel("Player " <> int(id) <> " Bonus", int(bonus), Render.color(id))

  defp overlay(_), do: []

  defp panel(title, hint, color) do
    [
      {:text, div(320 - byte_size(title) * 8, 2), 100, :default16px, color, 0x000020, title},
      {:text, div(320 - byte_size(hint) * 8, 2), 121, :default16px, 0xFFFFFF, 0x000020, hint},
      {:rect, 64, 91, 192, 54, 0x000020}
    ]
  end

  defp render_settings(state) do
    setup = Map.fetch!(state, :draft)

    rows =
      Enum.flat_map(1..4, fn id ->
        slot = Map.fetch!(setup, :slots)[id]
        marker = if id == Map.fetch!(state, :selected), do: ">", else: " "

        text(8, 53 + (id - 1) * 22, marker <> "P" <> int(id), 0xFFFFFF) ++
          text(48, 53 + (id - 1) * 22, mode_label(Map.fetch!(slot, :mode)), 0xFFFFFF) ++
          text(268, 53 + (id - 1) * 22, Setup.key_label(Map.fetch!(slot, :keys)), 0xFFFFFF) ++
          [{:rect, 8, 51 + (id - 1) * 22, 32, 20, Render.color(id)}]
      end)

    hint = if Setup.valid?(setup), do: "Enter: start  S: cancel", else: "Need 2 active players"

    {width, height} = Map.fetch!(setup, :board)

    text(8, 29, "PLAYER SETTINGS", 0xFFFFFF) ++
      rows ++
      text(8, 144, "R: Retract " <> if(Map.fetch!(setup, :retract), do: "ON", else: "OFF"), 0xFFFFFF) ++
      text(8, 162, "G: Board " <> int(width) <> "x" <> int(height), 0xFFFFFF) ++
      text(8, 180, "F/V: Step " <> int(Map.fetch!(setup, :step_ms)) <> "ms", 0xFFFFFF) ++
      text(8, 198, "Arrows: mode  C: keys", 0xA4B8C9) ++
      text(8, 217, hint, 0xFFFFFF) ++
      [{:rect, 0, 24, 320, 216, 0x000020}]
  end

  defp mode_label(:human), do: "Human"
  defp mode_label(:inactive), do: "Inactive"
  defp mode_label(_), do: "AI Simple"

  defp text(x, y, label, color), do: [{:text, x, y, :default16px, color, :transparent, label}]
  defp int(number), do: :erlang.integer_to_binary(number)
  defp short(number) when number >= 10000, do: int(div(number, 1000)) <> "k"
  defp short(number), do: int(number)
end
