defmodule Badge.App.Beamwars.Page.State do
  @moduledoc "Badge demo presentation, timing and tournament scores."
  @enforce_keys [:match, :layout]
  defstruct [:match, :layout, :result_until, round: 1, scores: %{}, paused: false, due_at: nil, frame: 0]
end

defmodule Badge.App.Beamwars.Page do
  @moduledoc """
  Four AI riders with automatic rematches. Space pauses; r restarts; b restores AI.
  Left/right, A/D, J/L and V/N take over riders 1–4 respectively.
  """
  use Badge.Page
  alias Badge.App.Beamwars.{Match, Render}
  alias __MODULE__.State

  @impl true
  def title, do: "BeamWars"
  @impl true
  def icon, do: :cross
  @impl true
  def init(options \\ []) do
    rules = Keyword.get(options, :rules, %{width: 78, height: 46})
    match = Match.demo(rules, Keyword.get(options, :seed, 1), Keyword.get(options, :profiles, %{}))
    %State{match: match, layout: Render.layout(match.game.config)}
  end

  @impl true
  def handle_key({:char, 32}, state), do: {:ok, %{state | paused: not state.paused, due_at: nil}}
  def handle_key({:char, char}, state) when char == ?r or char == ?R, do: {:ok, restart(state)}

  def handle_key({:char, char}, state) when char == ?b or char == ?B do
    match =
      Enum.reduce(1..4, state.match, fn id, match ->
        Match.control(match, id, {Badge.App.Beamwars.Bot, Badge.App.Beamwars.Bot.init(state.round * 31 + id * 13)})
      end)

    {:ok, %{state | match: match}}
  end

  def handle_key(event, state) do
    case key_binding(event) do
      nil ->
        :ignore

      {id, turn} ->
        match = state.match |> Match.control(id, :human) |> Match.command(id, turn)
        {:ok, %{state | match: match}}
    end
  end

  @impl true
  def tick(state), do: advance(state, :erlang.monotonic_time(:millisecond))
  @impl true
  def refresh(_state), do: 100

  @doc "Advances the shell against an explicit clock, allowing deterministic tests."
  def advance(%State{paused: true} = state, _now), do: state

  def advance(%State{result_until: deadline} = state, now) when is_integer(deadline) do
    if now >= deadline, do: restart(state), else: %{state | frame: state.frame + 1}
  end

  def advance(state, now) when is_integer(state.due_at) and now < state.due_at, do: state

  def advance(state, now) do
    match = Match.tick(state.match)

    scores =
      Enum.reduce(match.scores, state.scores, fn {id, score}, scores ->
        gain = score - Map.get(state.match.scores, id, 0)
        Map.update(scores, id, gain, &(&1 + gain))
      end)

    state = %{state | scores: scores, match: match, due_at: now + match.game.config.step_ms, frame: state.frame + 1}

    case match.game.status do
      :running -> state
      :draw -> %{state | result_until: now + 2000}
      {:winner, _id} -> %{state | result_until: now + 2000}
    end
  end

  defp restart(state) do
    profiles =
      Map.new(state.match.controllers, fn
        {id, {Badge.App.Beamwars.Bot, memory}} -> {id, memory.profile}
        {id, _} -> {id, :intermediate}
      end)

    match = Match.demo(state.match.game.config, state.round + 1, profiles)

    match =
      Enum.reduce(state.match.controllers, match, fn
        {id, :human}, match -> Match.control(match, id, :human)
        _, match -> match
      end)

    %{state | match: match, round: state.round + 1, result_until: nil, due_at: nil}
  end

  @impl true
  def render(state) do
    overlay(state) ++ hud(state) ++ Render.scene(state.match.game, state.layout, state.frame)
  end

  defp hud(state) do
    game = state.match.game

    scores =
      for id <- 1..4 do
        label = int(Map.get(state.scores, id, 0))
        {:text, 8 + (id - 1) * 47, 220, :default16px, Render.color(id), :transparent, label}
      end

    energy =
      case game.arena.next_shrink_tick do
        nil -> 0
        deadline -> max(deadline - game.tick, 0)
      end

    scores ++
      text(210, 213, "Board Energy", 0xFFFFFF) ++
      text(250, 224, int(energy), 0xFFFFFF)
  end

  defp overlay(%State{paused: true}), do: panel("PAUSED", "Space to resume", 0xFFFFFF)
  defp overlay(%State{match: %{game: %{status: :draw}}}), do: panel("DRAW", "Next round...", 0xA4B8C9)

  defp overlay(%State{match: %{game: %{status: {:winner, id}}}}),
    do: panel("P" <> int(id) <> " WINS", "Next round...", Render.color(id))

  defp overlay(_), do: []

  defp panel(title, hint, color) do
    text(div(320 - byte_size(title) * 8, 2), 100, title, color) ++
      text(div(320 - byte_size(hint) * 8, 2), 121, hint, 0xA4B8C9) ++
      [{:rect, 72, 91, 176, 54, 0x09131C}]
  end

  defp text(x, y, label, color), do: [{:text, x, y, :default16px, color, :transparent, label}]
  defp int(number), do: :erlang.integer_to_binary(number)
  defp key_binding({:move, turn}) when turn == :left or turn == :right, do: {1, turn}
  defp key_binding({:char, ?a}), do: {2, :left}
  defp key_binding({:char, ?d}), do: {2, :right}
  defp key_binding({:char, ?j}), do: {3, :left}
  defp key_binding({:char, ?l}), do: {3, :right}
  defp key_binding({:char, ?v}), do: {4, :left}
  defp key_binding({:char, ?n}), do: {4, :right}
  defp key_binding(_), do: nil
end
