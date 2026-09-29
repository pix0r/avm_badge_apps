defmodule Badge.App.Beamwars.Bot.Profile do
  @moduledoc "Tunable AI policy and reaction timing, measured in game ticks."
  defstruct search_limit: 160,
            reaction_ticks: 3,
            decision_delay: 1,
            aggression: 4,
            caution: 12,
            prediction_ticks: 6,
            safe_room: 24,
            space_weight: 1,
            runway_weight: 1,
            runway_limit: 8,
            tie_modulus: 11

  def new(%__MODULE__{} = profile), do: new(Map.to_list(Map.from_struct(profile)))
  def new(level) when is_atom(level), do: new(preset(level))

  def new(options) when is_list(options) do
    defaults = Map.from_struct(%__MODULE__{})

    settings =
      Enum.reduce(options, defaults, fn {key, value}, settings ->
        if not Map.has_key?(settings, key),
          do: raise(ArgumentError, "unknown AI parameter: #{inspect(key)}")

        minimum =
          if key in [:decision_delay, :aggression, :caution, :space_weight, :runway_weight],
            do: 0,
            else: 1

        if not is_integer(value) or value < minimum,
          do: raise(ArgumentError, "invalid AI parameter: #{inspect(key)}")

        Map.put(settings, key, value)
      end)

    if settings.decision_delay >= settings.reaction_ticks,
      do: raise(ArgumentError, "decision_delay must be less than reaction_ticks")

    %__MODULE__{
      search_limit: settings.search_limit,
      reaction_ticks: settings.reaction_ticks,
      decision_delay: settings.decision_delay,
      aggression: settings.aggression,
      caution: settings.caution,
      prediction_ticks: settings.prediction_ticks,
      safe_room: settings.safe_room,
      space_weight: settings.space_weight,
      runway_weight: settings.runway_weight,
      runway_limit: settings.runway_limit,
      tie_modulus: settings.tie_modulus
    }
  end

  defp preset(:beginner),
    do: [
      search_limit: 48,
      reaction_ticks: 5,
      decision_delay: 2,
      aggression: 1,
      prediction_ticks: 3
    ]

  defp preset(:intermediate), do: []

  defp preset(:expert),
    do: [
      search_limit: 320,
      reaction_ticks: 2,
      decision_delay: 1,
      aggression: 6,
      prediction_ticks: 8
    ]

  defp preset(:pro),
    do: [
      search_limit: 640,
      reaction_ticks: 1,
      decision_delay: 0,
      aggression: 8,
      prediction_ticks: 10
    ]

  defp preset(level), do: raise(ArgumentError, "unknown AI level: #{inspect(level)}")
end

defmodule Badge.App.Beamwars.Bot do
  @moduledoc "Deterministic pursuit and space-search pilot with delayed decisions."
  @behaviour Badge.App.Beamwars.Controller
  alias Badge.App.Beamwars.{Arena, Game, Player, State}
  alias __MODULE__.Profile

  @enforce_keys [:seed, :profile]
  defstruct [:seed, :profile, :pending, :due_tick, next_think_tick: 0]

  @type t :: %__MODULE__{
          seed: integer(),
          profile: %Profile{},
          pending: Player.turn(),
          due_tick: integer() | nil,
          next_think_tick: integer()
        }

  @impl true
  def init(seed), do: init(seed, :intermediate)
  def init(seed, options), do: %__MODULE__{seed: seed, profile: Profile.new(options)}

  @impl true
  def choose(%State{tick: tick}, _id, %__MODULE__{due_tick: due} = memory)
      when is_integer(due) and tick >= due do
    {memory.pending, %{memory | pending: nil, due_tick: nil}}
  end

  def choose(%State{tick: tick}, _id, %__MODULE__{next_think_tick: next} = memory)
      when tick < next,
      do: {nil, memory}

  def choose(%State{} = game, id, %__MODULE__{} = memory) do
    profile = memory.profile
    turn = plan(game, id, memory)
    memory = %{memory | next_think_tick: game.tick + profile.reaction_ticks}

    if profile.decision_delay == 0 do
      {turn, memory}
    else
      {nil, %{memory | pending: turn, due_tick: game.tick + profile.decision_delay}}
    end
  end

  defp plan(game, id, memory) do
    profile = memory.profile
    player = Map.fetch!(game.players, id)
    # Forecast our forward travel while thinking. No opponent gets pending inputs.
    {player, occupied} = project(player, game.occupied, profile.decision_delay)
    arena = Arena.advance(game.arena, game.config, game.tick + profile.decision_delay + 1)
    threats = opponent_destinations(game, id)
    opponents = for opponent <- Game.living(game), opponent.id != id, do: opponent
    choices = [{nil, 0}, {:left, 1}, {:right, 2}]

    candidates =
      for {turn, preference} <- choices,
          next = Player.move(player, turn),
          Arena.contains?(arena, player.position),
          free?(next.position, arena, occupied) do
        room = reachable([next.position], %{}, arena, occupied, profile.search_limit)
        risk = if Map.has_key?(threats, next.position), do: profile.caution, else: 0
        runway = runway(next.position, next.direction, arena, occupied, 0)
        pursuit = pursuit(next, opponents, profile.prediction_ticks)

        value =
          min(room, profile.safe_room) * profile.space_weight +
            min(runway, profile.runway_limit) * profile.runway_weight +
            pursuit * profile.aggression - risk

        safe = if runway >= profile.reaction_ticks - profile.decision_delay - 1, do: 1, else: 0
        tie = rem(memory.seed + game.tick + preference * 7, profile.tie_modulus)
        {{safe, value, tie, -preference}, turn}
      end

    best(candidates, nil)
  end

  defp project(player, occupied, 0), do: {player, occupied}

  defp project(player, occupied, ticks) do
    next = Player.move(player, nil)
    project(next, Map.put(occupied, next.position, player.id), ticks - 1)
  end

  defp pursuit(_player, [], _horizon), do: 0

  defp pursuit(player, opponents, horizon) do
    Enum.reduce(opponents, -1_000_000, fn opponent, best ->
      target = predict(opponent.position, opponent.direction, horizon)
      {x, y} = player.position
      {tx, ty} = target
      distance = abs(x - tx) + abs(y - ty)
      # Reward a trail aimed across an opponent's projected path.
      intercept =
        case player.direction do
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
      neighbors =
        for direction <- [:north, :east, :south, :west], do: Player.step(cell, direction)

      1 + reachable(neighbors ++ rest, Map.put(seen, cell, true), arena, occupied, remaining - 1)
    end
  end

  defp runway(cell, direction, arena, occupied, distance) do
    next = Player.step(cell, direction)

    if free?(next, arena, occupied),
      do: runway(next, direction, arena, occupied, distance + 1),
      else: distance
  end

  defp free?(cell, arena, occupied),
    do: Arena.contains?(arena, cell) and not Map.has_key?(occupied, cell)
end
