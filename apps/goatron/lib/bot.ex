defmodule Badge.App.Goatron.Bot do
  @moduledoc "Bounded space-search pilot with deterministic tie-breaking and opponent avoidance."
  @behaviour Badge.App.Goatron.Controller
  alias Badge.App.Goatron.{Arena, Game, Player, State}

  @enforce_keys [:seed]
  defstruct [:seed, search_limit: 160]
  @type t :: %__MODULE__{seed: integer(), search_limit: pos_integer()}

  @impl true
  def init(seed), do: %__MODULE__{seed: seed}

  @impl true
  def choose(%State{} = game, id, %__MODULE__{} = memory) do
    player = Map.fetch!(game.players, id)
    arena = Arena.advance(game.arena, game.config, game.tick + 1)
    threats = opponent_destinations(game, id)
    choices = [{nil, 0}, {:left, 1}, {:right, 2}]

    candidates =
      for {turn, preference} <- choices,
          next = Player.move(player, turn),
          Arena.contains?(arena, player.position),
          free?(next.position, arena, game.occupied) do
        room = reachable([next.position], %{}, arena, game.occupied, memory.search_limit)
        risk = if Map.has_key?(threats, next.position), do: 1, else: 0
        runway = runway(next.position, next.direction, arena, game.occupied, 0)
        tie = rem(memory.seed + game.tick + preference * 7, 11)
        {{-risk, room, runway, tie, -preference}, turn}
      end

    turn = best(candidates, nil)
    {turn, memory}
  end

  defp best([], nil), do: nil
  defp best([], {_score, turn}), do: turn
  defp best([candidate | rest], nil), do: best(rest, candidate)

  defp best([{score, _} = candidate | rest], {previous, _} = current) do
    best(rest, if(score > previous, do: candidate, else: current))
  end

  defp opponent_destinations(game, id) do
    for player <- Game.living(game), player.id != id, turn <- [nil, :left, :right], into: %{} do
      {Player.move(player, turn).position, true}
    end
  end

  defp reachable([], _seen, _arena, _occupied, _remaining), do: 0
  defp reachable(_frontier, _seen, _arena, _occupied, 0), do: 0

  defp reachable([cell | rest], seen, arena, occupied, remaining) do
    if Map.has_key?(seen, cell) or not free?(cell, arena, occupied) do
      reachable(rest, seen, arena, occupied, remaining)
    else
      neighbors = for direction <- [:north, :east, :south, :west], do: Player.step(cell, direction)
      1 + reachable(neighbors ++ rest, Map.put(seen, cell, true), arena, occupied, remaining - 1)
    end
  end

  defp runway(cell, direction, arena, occupied, distance) do
    next = Player.step(cell, direction)
    if free?(next, arena, occupied), do: runway(next, direction, arena, occupied, distance + 1), else: distance
  end

  defp free?(cell, arena, occupied),
    do: Arena.contains?(arena, cell) and not Map.has_key?(occupied, cell)
end
