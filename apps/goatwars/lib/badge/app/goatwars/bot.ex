defmodule Badge.App.Goatwars.Bot do
  @moduledoc "Deterministic pursuit and space-search pilot with delayed decisions."
  @behaviour Badge.App.Goatwars.Controller
  alias Badge.App.Goatwars.{Arena, Game, Player}
  alias __MODULE__.Profile

  @type t :: %{
          seed: integer(),
          profile: Profile.t(),
          pending: Player.turn(),
          due_tick: integer() | nil,
          next_think_tick: integer()
        }

  @impl true
  def init(seed), do: init(seed, :intermediate)

  def init(seed, options),
    do: %{seed: seed, profile: Profile.new(options), pending: nil, due_tick: nil, next_think_tick: 0}

  @impl true
  def choose(%{tick: tick}, _id, %{due_tick: due} = memory)
      when is_integer(due) and tick >= due do
    {Map.fetch!(memory, :pending), %{memory | pending: nil, due_tick: nil}}
  end

  def choose(%{tick: tick}, _id, %{next_think_tick: next} = memory)
      when tick < next,
      do: {nil, memory}

  def choose(%{players: _, tick: _} = game, id, %{profile: _} = memory) do
    profile = Map.fetch!(memory, :profile)
    turn = plan(game, id, memory)
    memory = %{memory | next_think_tick: Map.fetch!(game, :tick) + Map.fetch!(profile, :reaction_ticks)}

    if Map.fetch!(profile, :decision_delay) == 0 do
      {turn, memory}
    else
      {nil, %{memory | pending: turn, due_tick: Map.fetch!(game, :tick) + Map.fetch!(profile, :decision_delay)}}
    end
  end

  defp plan(game, id, memory) do
    profile = Map.fetch!(memory, :profile)
    player = Map.fetch!(Map.fetch!(game, :players), id)
    # Forecast our forward travel while thinking. No opponent gets pending inputs.
    {player, occupied} = project(player, Map.fetch!(game, :occupied), Map.fetch!(profile, :decision_delay))

    arena =
      Arena.advance(Map.fetch!(game, :arena), Map.fetch!(game, :config), Map.fetch!(game, :tick) + Map.fetch!(profile, :decision_delay) + 1)

    threats = opponent_destinations(game, id)
    opponents = for opponent <- Game.living(game), Map.fetch!(opponent, :id) != id, do: opponent
    choices = [{nil, 0}, {:left, 1}, {:right, 2}]

    candidates =
      for {turn, preference} <- choices,
          next = Player.move(player, turn),
          Arena.contains?(arena, Map.fetch!(player, :position)),
          free?(Map.fetch!(next, :position), arena, occupied) do
        room =
          reachable(
            [Map.fetch!(next, :position)],
            %{},
            arena,
            occupied,
            min(Map.fetch!(profile, :search_limit), Map.fetch!(profile, :safe_room))
          )

        risk = if Map.has_key?(threats, Map.fetch!(next, :position)), do: Map.fetch!(profile, :caution), else: 0
        limit = max(Map.fetch!(profile, :runway_limit), Map.fetch!(profile, :reaction_ticks) - Map.fetch!(profile, :decision_delay) - 1)
        runway = runway(Map.fetch!(next, :position), Map.fetch!(next, :direction), arena, occupied, 0, limit)
        pursuit = pursuit(next, opponents, Map.fetch!(profile, :prediction_ticks))

        value =
          min(room, Map.fetch!(profile, :safe_room)) * Map.fetch!(profile, :space_weight) +
            min(runway, Map.fetch!(profile, :runway_limit)) * Map.fetch!(profile, :runway_weight) +
            pursuit * Map.fetch!(profile, :aggression) - risk

        safe = if runway >= Map.fetch!(profile, :reaction_ticks) - Map.fetch!(profile, :decision_delay) - 1, do: 1, else: 0
        tie = rem(Map.fetch!(memory, :seed) + Map.fetch!(game, :tick) + preference * 7, Map.fetch!(profile, :tie_modulus))
        {{safe, value, tie, -preference}, turn}
      end

    best(candidates, nil)
  end

  defp project(player, occupied, 0), do: {player, occupied}

  defp project(player, occupied, ticks) do
    next = Player.move(player, nil)
    project(next, Map.put(occupied, Map.fetch!(next, :position), Map.fetch!(player, :id)), ticks - 1)
  end

  defp pursuit(_player, [], _horizon), do: 0

  defp pursuit(player, opponents, horizon) do
    Enum.reduce(opponents, -1_000_000, fn opponent, best ->
      target = predict(Map.fetch!(opponent, :position), Map.fetch!(opponent, :direction), horizon)
      {x, y} = Map.fetch!(player, :position)
      {tx, ty} = target
      distance = abs(x - tx) + abs(y - ty)
      # Reward a trail aimed across an opponent's projected path.
      intercept =
        case Map.fetch!(player, :direction) do
          :east -> ty == y and tx > x and tx - x <= horizon
          :west -> ty == y and tx < x and x - tx <= horizon
          :south -> tx == x and ty > y and ty - y <= horizon
          :north -> tx == x and ty < y and y - ty <= horizon
        end

      max(best, -distance + if(intercept, do: horizon, else: 0))
    end)
  end

  defp predict(position, _direction, 0), do: position

  defp predict(position, direction, ticks),
    do: predict(Player.step(position, direction), direction, ticks - 1)

  defp best([], nil), do: nil
  defp best([], {_score, turn}), do: turn
  defp best([candidate | rest], nil), do: best(rest, candidate)

  defp best([{score, _} = candidate | rest], {previous, _} = current) do
    best(rest, if(score > previous, do: candidate, else: current))
  end

  defp opponent_destinations(game, id) do
    for player <- Game.living(game), Map.fetch!(player, :id) != id, turn <- [nil, :left, :right], into: %{} do
      {Map.fetch!(Player.move(player, turn), :position), true}
    end
  end

  defp reachable([], _seen, _arena, _occupied, _remaining), do: 0
  defp reachable(_frontier, _seen, _arena, _occupied, 0), do: 0

  defp reachable([cell | rest], seen, arena, occupied, remaining) do
    if Map.has_key?(seen, cell) or not free?(cell, arena, occupied) do
      reachable(rest, seen, arena, occupied, remaining)
    else
      neighbors =
        for direction <- [:north, :east, :south, :west], do: Player.step(cell, direction)

      1 + reachable(neighbors ++ rest, Map.put(seen, cell, true), arena, occupied, remaining - 1)
    end
  end

  defp runway(_cell, _direction, _arena, _occupied, distance, limit) when distance >= limit,
    do: distance

  defp runway(cell, direction, arena, occupied, distance, limit) do
    next = Player.step(cell, direction)

    if free?(next, arena, occupied),
      do: runway(next, direction, arena, occupied, distance + 1, limit),
      else: distance
  end

  defp free?(cell, arena, occupied),
    do: Arena.contains?(arena, cell) and not Map.has_key?(occupied, cell)
end
