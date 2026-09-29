defmodule Badge.App.Beamwars.Game do
  @moduledoc """
  Pure, simultaneous lightcycle rules. Left/right commands apply for one tick;
  omission preserves heading. Trails remain occupied after elimination.
  Contraction removes the outer ring before movement and sweeps bikes on it.
  """
  alias Badge.App.Beamwars.{Arena, Config, Player, State}

  @type event :: {:crashed, integer(), Player.position()} | {:arena_shrank, non_neg_integer()}
  @type inputs :: %{integer() => :left | :right}

  @spec new(map(), [map()]) :: {:ok, State.t()} | {:error, atom()}
  def new(options, roster) do
    with {:ok, config} <- Config.new(options),
         arena = Arena.new(config),
         {:ok, players} <- build_roster(roster, arena) do
      occupied = players |> Enum.map(fn {id, player} -> {player.position, id} end) |> Map.new()
      trails = players |> Enum.map(fn {id, player} -> {id, [player.position]} end) |> Map.new()

      {:ok,
       %State{config: config, arena: arena, players: players, occupied: occupied, trails: trails}}
    end
  end

  @spec step(State.t(), inputs()) :: {:ok, State.t(), [event()]} | {:error, :invalid_inputs}
  def step(%State{} = state, inputs) do
    with :ok <- validate_inputs(inputs, state.players) do
      advance(state, inputs)
    end
  end

  defp advance(%State{status: status} = state, _inputs) when status != :running,
    do: {:ok, state, []}

  defp advance(state, inputs) do
    tick = state.tick + 1
    arena = Arena.advance(state.arena, state.config, tick)

    proposals =
      living(state)
      |> Enum.map(fn player ->
        {player.id, Player.move(player, Map.get(inputs, player.id))}
      end)
      |> Map.new()

    destinations =
      Enum.reduce(Map.values(proposals), %{}, fn player, counts ->
        Map.put(counts, player.position, Map.get(counts, player.position, 0) + 1)
      end)

    {players, occupied, crashes} =
      Enum.reduce(ordered(proposals), {state.players, state.occupied, []}, fn {_id, proposed},
                                                                              acc ->
        resolve(state, arena, proposed, destinations, acc)
      end)

    trails =
      Enum.reduce(players, state.trails, fn
        {id, %Player{alive: true, position: position}}, trails ->
          Map.put(trails, id, [position | Map.get(trails, id, [])])

        _, trails ->
          trails
      end)

    occupied = clear_blasts(occupied, crashes, state.config.explosion_radius)

    occupied =
      Enum.reduce(players, occupied, fn
        {id, %Player{alive: true, position: position}}, occupied ->
          Map.put(occupied, position, id)

        _, occupied ->
          occupied
      end)

    next = %{
      state
      | tick: tick,
        arena: arena,
        players: players,
        occupied: occupied,
        trails: trails
    }

    next = cleanup(next)
    next = %{next | status: outcome(living(next))}
    events = contraction_events(state.arena, arena) ++ Enum.reverse(crashes)
    {:ok, next, events}
  end

  defp resolve(state, arena, proposed, destinations, {players, occupied, crashes}) do
    original = Map.fetch!(state.players, proposed.id)

    collision? =
      not Arena.contains?(arena, original.position) or
        not Arena.contains?(arena, proposed.position) or
        Map.has_key?(state.occupied, proposed.position) or
        Map.fetch!(destinations, proposed.position) > 1

    if collision? do
      dead = %{original | alive: false, direction: proposed.direction}

      {Map.put(players, dead.id, dead), occupied,
       [{:crashed, dead.id, proposed.position} | crashes]}
    else
      {Map.put(players, proposed.id, proposed), Map.put(occupied, proposed.position, proposed.id),
       crashes}
    end
  end

  @doc "Retracts dead beams by one configured chunk without advancing the round clock."
  def cleanup(%State{config: %Config{retract_speed: 0}} = state), do: state

  def cleanup(state) do
    {occupied, trails} =
      Enum.reduce(state.players, {state.occupied, state.trails}, fn
        {id, %Player{alive: false}}, {occupied, trails} ->
          {occupied, remaining} =
            retract(Map.get(trails, id, []), occupied, id, state.config.retract_speed)

          {occupied, Map.put(trails, id, remaining)}

        _, acc ->
          acc
      end)

    %{state | occupied: occupied, trails: trails}
  end

  defp retract(trail, occupied, _id, 0), do: {occupied, trail}
  defp retract([], occupied, _id, _count), do: {occupied, []}

  defp retract([cell | rest], occupied, id, count) do
    occupied = if Map.get(occupied, cell) == id, do: Map.delete(occupied, cell), else: occupied
    retract(rest, occupied, id, count - 1)
  end

  defp clear_blasts(occupied, _crashes, 0), do: occupied

  defp clear_blasts(occupied, crashes, radius) do
    Map.new(
      Enum.reject(occupied, fn {{x, y}, _id} ->
        Enum.any?(crashes, fn {:crashed, _, {cx, cy}} ->
          (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius
        end)
      end)
    )
  end

  @doc "Living players, ordered by stable ID."
  def living(%State{players: players}) do
    for {_id, %Player{alive: true} = player} <- ordered(players), do: player
  end

  defp build_roster(roster, arena) when is_list(roster) and length(roster) >= 2 do
    build_players(roster, arena, %{})
  end

  defp build_roster(_, _arena), do: {:error, :invalid_players}

  defp build_players([], _arena, players), do: {:ok, players}

  defp build_players([entry | rest], arena, players) do
    with {:ok, player} <- Player.new(entry),
         true <- Arena.contains?(arena, player.position),
         false <- Map.has_key?(players, player.id),
         false <- Enum.any?(Map.values(players), &(&1.position == player.position)) do
      build_players(rest, arena, Map.put(players, player.id, player))
    else
      _ -> {:error, :invalid_players}
    end
  end

  defp validate_inputs(inputs, players) when is_map(inputs) do
    valid? =
      Enum.all?(inputs, fn {id, turn} ->
        match?(%Player{alive: true}, Map.get(players, id)) and (turn == :left or turn == :right)
      end)

    if valid?, do: :ok, else: {:error, :invalid_inputs}
  end

  defp validate_inputs(_, _), do: {:error, :invalid_inputs}
  defp outcome([]), do: :draw
  defp outcome([player]), do: {:winner, player.id}
  defp outcome(_), do: :running
  defp contraction_events(%Arena{inset: inset}, %Arena{inset: inset}), do: []
  defp contraction_events(_, arena), do: [{:arena_shrank, arena.inset}]

  defp ordered(map), do: :lists.keysort(1, Map.to_list(map))
end
