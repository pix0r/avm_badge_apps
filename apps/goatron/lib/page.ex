defmodule Badge.App.Goatron.Page.State do
  @moduledoc "Badge demo presentation, timing and tournament scores."
  @enforce_keys [:match, :layout]
  defstruct [:match, :layout, :result_until, round: 1, wins: %{}, paused: false, due_at: nil, frame: 0]
end

defmodule Badge.App.Goatron.Page do
  @moduledoc """
  Four AI riders with automatic rematches. Space pauses; r restarts; b restores AI.
  Left/right, A/D, J/L and V/N take over riders 1–4 respectively.
  """
  use Badge.Page
  alias Badge.App.Goatron.{Arena, Match, Render}
  alias __MODULE__.State

  @impl true
  def title, do: "GoaTRON"
  @impl true
  def icon, do: :cross
  @impl true
  def init do
    match = Match.demo()
    %State{match: match, layout: Render.layout(match.game.config)}
  end

  @impl true
  def handle_key({:char, 32}, state), do: {:ok, %{state | paused: not state.paused, due_at: nil}}
  def handle_key({:char, char}, state) when char == ?r or char == ?R, do: {:ok, restart(state)}

  def handle_key({:char, char}, state) when char == ?b or char == ?B do
    match =
      Enum.reduce(1..4, state.match, fn id, match ->
        Match.control(match, id, {Badge.App.Goatron.Bot, Badge.App.Goatron.Bot.init(state.round * 31 + id * 13)})
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
    state = %{state | match: match, due_at: now + match.game.config.step_ms, frame: state.frame + 1}

    case match.game.status do
      :running -> state
      :draw -> %{state | result_until: now + 2000}
      {:winner, id} -> %{state | result_until: now + 2000, wins: Map.update(state.wins, id, 1, &(&1 + 1))}
    end
  end

  defp restart(state) do
    match = Match.demo(state.match.game.config, state.round + 1)

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

    countdown =
      case game.arena.next_shrink_tick do
        nil ->
          "FINAL ARENA"

        deadline ->
          if Arena.warning?(game.arena, game.config, game.tick),
            do: "WALL IN " <> int(max(deadline - game.tick, 0)),
            else: "SHRINK " <> int(max(deadline - game.tick, 0))
      end

    banner = if state.paused, do: "PAUSED", else: countdown

    status =
      text(10, 26, "ROUND " <> int(state.round) <> " / " <> int(game.tick), 0xA4B8C9) ++
        text(207, 26, banner, 0xFFCA62)

    scores =
      for id <- 1..4 do
        player = game.players[id]
        label = "P" <> int(id) <> " " <> int(Map.get(state.wins, id, 0))
        color = if player.alive, do: Render.color(id), else: 0x52616D
        {:text, 12 + (id - 1) * 79, 217, :default16px, color, :transparent, label}
      end

    status ++ scores
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
