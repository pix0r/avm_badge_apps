defmodule Badge.App.Goatwars.Page do
  @moduledoc "GoatWars badge adapter. S opens player settings; Space pauses; R rematches."
  use Badge.Page
  alias Badge.App.Goatwars.{Bot, Game, Match, Render, Setup}
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
    match = Match.demo(rules, Keyword.get(options, :seed, 1), Setup.controllers(setup), record_replay: false)
    setup = %{setup | retract: match.game.config.retract_speed > 0}
    countdown = Keyword.get(options, :countdown_ms, 3000)

    State.new(%{
      match: match,
      layout: Render.layout(match.game.config),
      setup: setup,
      started: countdown == 0,
      launch_remaining: countdown
    })
  end

  @impl true
  def handle_key(event, %{screen: :settings} = state), do: settings_key(event, state)
  def handle_key({:char, ?s}, state), do: {:ok, %{state | screen: :settings, draft: state.setup}}

  def handle_key({:char, 32}, state),
    do: {:ok, %{state | paused: not state.paused, due_at: nil, launch_at: nil}}

  def handle_key({:char, char}, state) when char == ?r or char == ?R, do: {:ok, restart(state)}

  def handle_key({:char, char}, state) when char == ?b or char == ?B do
    match =
      Enum.reduce(Map.keys(state.match.controllers), state.match, fn id, match ->
        Match.control(match, id, {Bot, Bot.init(state.round * 31 + id * 13)})
      end)

    setup =
      Enum.reduce(Map.keys(match.controllers), state.setup, &Setup.mode(&2, &1, :intermediate))

    {:ok, %{state | match: match, setup: setup}}
  end

  def handle_key(event, state) do
    case Setup.binding(state.setup, event) do
      {id, turn} ->
        match = state.match |> Match.control(id, :human) |> Match.command(id, turn)
        {:ok, %{state | match: match, setup: Setup.mode(state.setup, id, :human)}}

      nil ->
        :ignore
    end
  end

  defp settings_key({:move, :up}, state),
    do: {:ok, %{state | selected: max(state.selected - 1, 1)}}

  defp settings_key({:move, :down}, state),
    do: {:ok, %{state | selected: min(state.selected + 1, 4)}}

  defp settings_key({:move, turn}, state) when turn == :left or turn == :right do
    delta = if turn == :left, do: -1, else: 1
    {:ok, %{state | draft: Setup.cycle_mode(state.draft, state.selected, delta)}}
  end

  defp settings_key({:char, ?c}, state),
    do: {:ok, %{state | draft: Setup.cycle_keys(state.draft, state.selected)}}

  defp settings_key({:char, ?r}, state),
    do: {:ok, %{state | draft: %{state.draft | retract: not state.draft.retract}}}

  defp settings_key({:char, ?s}, state),
    do: {:ok, %{state | screen: :game, draft: nil, launch_at: nil, due_at: nil}}

  defp settings_key(:enter, state) do
    if Setup.valid?(state.draft),
      do: {:ok, restart(%{state | setup: state.draft, screen: :game, draft: nil})},
      else: {:ok, state}
  end

  defp settings_key({:edit, :newline}, state), do: settings_key(:enter, state)
  defp settings_key({:char, 13}, state), do: settings_key(:enter, state)
  defp settings_key(_, _), do: :ignore

  @impl true
  def tick(state), do: advance(state, :erlang.monotonic_time(:millisecond))
  @impl true
  def refresh(_state), do: 100

  @doc "Advances against an explicit clock for deterministic shell tests."
  def advance(%{screen: :settings} = state, _now), do: state
  def advance(%{paused: true} = state, _now), do: state

  def advance(%{started: false} = state, now) do
    deadline = state.launch_at || now + state.launch_remaining
    remaining = max(deadline - now, 0)
    state = %{state | launch_at: deadline, launch_remaining: remaining, frame: state.frame + 1}
    if remaining == 0, do: advance(%{state | started: true}, now), else: state
  end

  def advance(%{result_until: deadline} = state, now) when is_integer(deadline) do
    if now >= deadline do
      restart(state)
    else
      match = %{state.match | game: Game.cleanup(state.match.game)}
      animate(%{state | match: match})
    end
  end

  def advance(state, now) when is_integer(state.due_at) and now < state.due_at, do: state

  def advance(state, now) do
    match = Match.tick(state.match)

    scores =
      Enum.reduce(match.totals, state.scores, fn {id, score}, scores ->
        gain = score - Map.get(state.match.totals, id, 0)
        Map.put(scores, id, Map.get(scores, id, 0) + gain)
      end)

    state =
      animate(%{state | scores: scores, match: match, due_at: now + match.game.config.step_ms})

    effects =
      for {:crashed, id, position} <- match.events,
          do: Render.Explosion.new(id, position)

    state = %{state | effects: effects ++ state.effects}
    if match.game.status == :running, do: state, else: %{state | result_until: now + 2000}
  end

  defp animate(state) do
    effects = for effect <- state.effects, effect.age < 5, do: %{effect | age: effect.age + 1}
    %{state | effects: effects, frame: state.frame + 1}
  end

  defp restart(state) do
    config = %{
      state.match.game.config
      | retract_speed:
          if(state.setup.retract,
            do:
              if(state.match.game.config.retract_speed > 0,
                do: state.match.game.config.retract_speed,
                else: 8
              ),
            else: 0
          )
    }

    controllers = Setup.controllers(state.setup)
    match = Match.demo(config, state.round + 1, controllers, record_replay: false)

    %{
      state
      | match: match,
        round: state.round + 1,
        result_until: nil,
        due_at: nil,
        started: false,
        launch_at: nil,
        launch_remaining: 3000,
        effects: [],
        paused: false
    }
  end

  @impl true
  def render(%{screen: :settings} = state), do: render_settings(state)

  def render(state) do
    overlay(state) ++
      Render.explosions(state.effects, state.layout, state.match.game) ++
      hud(state) ++ cannons(state) ++ Render.scene(state.match.game, state.layout, state.frame)
  end

  defp cannons(%{started: false} = state), do: Render.cannons(state.match.game, state.layout)
  defp cannons(_), do: []

  defp hud(state) do
    game = state.match.game

    scores =
      Enum.flat_map(1..4, fn id ->
        x = 4 + (id - 1) * 43

        text(x, 210, short(Map.get(state.match.scores, id, 0)), 0xFFFFFF) ++
          text(x, 224, short(Map.get(state.scores, id, 0)), 0xFFFFFF) ++
          [{:rect, x, 209, 36, 1, Render.color(id)}]
      end)

    energy =
      case game.arena.next_shrink_tick do
        nil -> 0
        deadline -> max(deadline - game.tick, 0)
      end

    scores ++
      text(180, 210, "Energy", 0xFFFFFF) ++
      text(180, 224, int(energy), 0xFFFFFF) ++
      text(256, 210, "Bonus", 0xFFFFFF) ++ text(256, 224, int(state.match.bonus), 0xFFFFFF)
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
    setup = state.draft

    rows =
      Enum.flat_map(1..4, fn id ->
        slot = setup.slots[id]
        marker = if id == state.selected, do: ">", else: " "

        text(8, 57 + (id - 1) * 27, marker <> "P" <> int(id), 0xFFFFFF) ++
          text(48, 57 + (id - 1) * 27, Setup.label(slot.mode), 0xFFFFFF) ++
          text(268, 57 + (id - 1) * 27, Setup.key_label(slot.keys), 0xFFFFFF) ++
          [{:rect, 8, 55 + (id - 1) * 27, 32, 20, Render.color(id)}]
      end)

    hint = if Setup.valid?(setup), do: "Enter: start  S: cancel", else: "Need 2 active players"

    text(8, 29, "PLAYER SETTINGS", 0xFFFFFF) ++
      rows ++
      text(8, 168, "R: Retract " <> if(setup.retract, do: "ON", else: "OFF"), 0xFFFFFF) ++
      text(8, 192, "Arrows: mode  C: keys", 0xA4B8C9) ++
      text(8, 217, hint, 0xFFFFFF) ++
      [{:rect, 0, 24, 320, 216, 0x000020}]
  end

  defp text(x, y, label, color), do: [{:text, x, y, :default16px, color, :transparent, label}]
  defp int(number), do: :erlang.integer_to_binary(number)
  defp short(number) when number >= 10000, do: int(div(number, 1000)) <> "k"
  defp short(number), do: int(number)
end
