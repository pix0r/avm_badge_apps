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
      Keyword.get(options, :rules, %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8})

    setup = Setup.new(Keyword.get(options, :profiles, %{}))
    seed = Keyword.get(options, :seed, 1)
    match = Match.demo(rules, seed, controllers(setup, seed), record_replay: false)
    match = if Keyword.get(options, :compact, true), do: %{match | game: Game.compact(Map.fetch!(match, :game))}, else: match
    setup = %{setup | retract: Map.fetch!(Map.fetch!(Map.fetch!(match, :game), :config), :retract_speed) > 0}
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
  def refresh(_state), do: 100

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
      animate(%{state | match: match})
    end
  end

  def advance(state, now) when is_integer(state.due_at) and now < state.due_at, do: state

  def advance(state, now) do
    match = Match.tick(Map.fetch!(state, :match))

    scores =
      Enum.reduce(Map.fetch!(match, :totals), Map.fetch!(state, :scores), fn {id, score}, scores ->
        gain = score - Map.get(Map.fetch!(Map.fetch!(state, :match), :totals), id, 0)
        Map.put(scores, id, Map.get(scores, id, 0) + gain)
      end)

    state =
      animate(%{state | scores: scores, match: match, due_at: now + Map.fetch!(Map.fetch!(Map.fetch!(match, :game), :config), :step_ms)})

    effects =
      for {:crashed, id, position} <- Map.fetch!(match, :events),
          do: Render.Explosion.new(id, position)

    state = %{state | effects: effects ++ Map.fetch!(state, :effects)}
    if Map.fetch!(Map.fetch!(match, :game), :status) == :running, do: state, else: %{state | result_until: now + 2000}
  end

  defp animate(state) do
    effects = for effect <- Map.fetch!(state, :effects), Map.fetch!(effect, :age) < 5, do: %{effect | age: Map.fetch!(effect, :age) + 1}
    %{state | effects: effects, frame: Map.fetch!(state, :frame) + 1}
  end

  defp restart(state) do
    config = %{
      Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :config)
      | retract_speed:
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

  defp hud(state) do
    game = Map.fetch!(Map.fetch!(state, :match), :game)

    scores =
      Enum.flat_map(1..4, fn id ->
        x = 4 + (id - 1) * 43

        label =
          if :lists.any(fn effect -> Map.fetch!(effect, :id) == id end, Map.fetch!(state, :effects)),
            do: "BAA!",
            else: short(Map.get(Map.fetch!(Map.fetch!(state, :match), :scores), id, 0))

        text(x, 210, label, 0xFFFFFF) ++
          text(x, 224, short(Map.get(Map.fetch!(state, :scores), id, 0)), 0xFFFFFF) ++
          [{:rect, x, 209, 36, 1, Render.color(id)}]
      end)

    energy =
      case Map.fetch!(Map.fetch!(game, :arena), :next_shrink_tick) do
        nil -> 0
        deadline -> max(deadline - Map.fetch!(game, :tick), 0)
      end

    scores ++
      text(180, 210, "Energy", 0xFFFFFF) ++
      text(180, 224, int(energy), 0xFFFFFF) ++
      text(256, 210, "Bonus", 0xFFFFFF) ++ text(256, 224, int(Map.fetch!(Map.fetch!(state, :match), :bonus)), 0xFFFFFF)
  end

  defp overlay(%{paused: true}), do: panel("PAUSED", "Space to resume", 0xFFFFFF)

  defp overlay(%{started: false, launch_remaining: remaining}),
    do: panel(int(div(remaining + 999, 1000)), "READY", 0xFFFFFF)

  defp overlay(%{match: %{game: %{status: :draw}}}), do: panel("DRAW", "No bonus", 0xFFFFFF)

  defp overlay(%{match: %{awarded_bonus: {id, bonus}}}),
    do: panel("Player " <> int(id) <> " Bonus", int(bonus), Render.color(id))

  defp overlay(_), do: []

  defp panel(title, hint, color) do
    text(div(320 - byte_size(title) * 8, 2), 100, title, color) ++
      text(div(320 - byte_size(hint) * 8, 2), 121, hint, 0xFFFFFF) ++
      [{:rect, 64, 91, 192, 54, 0x000020}]
  end

  defp render_settings(state) do
    setup = Map.fetch!(state, :draft)

    rows =
      Enum.flat_map(1..4, fn id ->
        slot = Map.fetch!(setup, :slots)[id]
        marker = if id == Map.fetch!(state, :selected), do: ">", else: " "

        text(8, 57 + (id - 1) * 27, marker <> "P" <> int(id), 0xFFFFFF) ++
          text(48, 57 + (id - 1) * 27, mode_label(Map.fetch!(slot, :mode)), 0xFFFFFF) ++
          text(268, 57 + (id - 1) * 27, Setup.key_label(Map.fetch!(slot, :keys)), 0xFFFFFF) ++
          [{:rect, 8, 55 + (id - 1) * 27, 32, 20, Render.color(id)}]
      end)

    hint = if Setup.valid?(setup), do: "Enter: start  S: cancel", else: "Need 2 active players"

    text(8, 29, "PLAYER SETTINGS", 0xFFFFFF) ++
      rows ++
      text(8, 168, "R: Retract " <> if(Map.fetch!(setup, :retract), do: "ON", else: "OFF"), 0xFFFFFF) ++
      text(8, 192, "Arrows: mode  C: keys", 0xA4B8C9) ++
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
