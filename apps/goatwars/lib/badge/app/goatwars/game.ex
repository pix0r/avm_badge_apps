defmodule Badge.App.Goatwars.Game do
  @moduledoc """
  Pure, simultaneous lightcycle rules. Left/right commands apply for one tick;
  omission preserves heading. Explosions and retraction clear trails when enabled.
  Contraction removes the outer ring before movement and sweeps bikes on it.
  """
  alias Badge.App.Goatwars.{Arena, Board, Config, Player, State}

  @type event :: {:crashed, integer(), Player.position()} | {:arena_shrank, non_neg_integer()}
  @type inputs :: %{integer() => :left | :right}

  @spec new(map(), [map()]) :: {:ok, State.t()} | {:error, atom()}
  def new(options, roster) do
    with {:ok, config} <- Config.new(options),
         arena = Arena.new(config),
         {:ok, players} <- build_roster(roster, arena) do
      occupied = players |> Enum.map(fn {id, player} -> {Map.fetch!(player, :position), id} end) |> Map.new()
      trails = players |> Enum.map(fn {id, player} -> {id, [Map.fetch!(player, :position)]} end) |> Map.new()

      {:ok, State.new(%{config: config, arena: arena, players: players, occupied: occupied, trails: trails})}
    end
  end

  @doc "Uses a fixed bitmap and packed trails for the four badge players."
  def compact(%{occupied: occupied} = state) when is_map(occupied) do
    trails =
      Enum.reduce(Map.fetch!(state, :trails), %{}, fn {id, cells}, trails ->
        bytes = Enum.reduce(:lists.reverse(cells), <<>>, fn {x, y}, bytes -> <<x::16, y::16, bytes::binary>> end)
        Map.put(trails, id, bytes)
      end)

    %{state | occupied: Board.new(Map.fetch!(state, :config), occupied), trails: trails}
  end

  def compact(state), do: state

  @spec step(State.t(), inputs()) :: {:ok, State.t(), [event()]} | {:error, :invalid_inputs}
  def step(%{players: _, config: _} = state, inputs) do
    with :ok <- validate_inputs(inputs, Map.fetch!(state, :players)) do
      advance(state, inputs)
    end
  end

  defp advance(%{status: status} = state, _inputs) when status != :running,
    do: {:ok, state, []}

  defp advance(state, inputs) do
    tick = Map.fetch!(state, :tick) + 1
    arena = Arena.advance(Map.fetch!(state, :arena), Map.fetch!(state, :config), tick)

    proposals =
      living(state)
      |> Enum.map(fn player ->
        {Map.fetch!(player, :id), Player.move(player, Map.get(inputs, Map.fetch!(player, :id)))}
      end)
      |> Map.new()

    destinations =
      Enum.reduce(Map.values(proposals), %{}, fn player, counts ->
        Map.put(counts, Map.fetch!(player, :position), Map.get(counts, Map.fetch!(player, :position), 0) + 1)
      end)

    {players, occupied, crashes} =
      Enum.reduce(ordered(proposals), {Map.fetch!(state, :players), Map.fetch!(state, :occupied), []}, fn {_id, proposed}, acc ->
        resolve(state, arena, proposed, destinations, acc)
      end)

    trails =
      Enum.reduce(players, Map.fetch!(state, :trails), fn
        {id, %{alive: true, position: position}}, trails ->
          Map.put(trails, id, prepend(position, Map.get(trails, id, [])))

        _, trails ->
          trails
      end)

    occupied = clear_blasts(occupied, crashes, Map.fetch!(Map.fetch!(state, :config), :explosion_radius))

    occupied =
      Enum.reduce(players, occupied, fn
        {id, %{alive: true, position: position}}, occupied ->
          Board.put(occupied, position, id)

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
    events = contraction_events(Map.fetch!(state, :arena), arena) ++ Enum.reverse(crashes)
    {:ok, next, events}
  end

  defp resolve(state, arena, proposed, destinations, {players, occupied, crashes}) do
    original = Map.fetch!(Map.fetch!(state, :players), Map.fetch!(proposed, :id))

    collision? =
      not Arena.contains?(arena, Map.fetch!(original, :position)) or
        not Arena.contains?(arena, Map.fetch!(proposed, :position)) or
        Board.has?(Map.fetch!(state, :occupied), Map.fetch!(proposed, :position)) or
        Map.fetch!(destinations, Map.fetch!(proposed, :position)) > 1

    if collision? do
      dead = %{original | alive: false, direction: Map.fetch!(proposed, :direction)}

      {Map.put(players, Map.fetch!(dead, :id), dead), occupied,
       [{:crashed, Map.fetch!(dead, :id), Map.fetch!(proposed, :position)} | crashes]}
    else
      {Map.put(players, Map.fetch!(proposed, :id), proposed),
       Board.put(occupied, Map.fetch!(proposed, :position), Map.fetch!(proposed, :id)), crashes}
    end
  end

  @doc "Retracts dead beams by one configured chunk without advancing the round clock."
  def cleanup(%{config: %{retract_speed: 0}} = state), do: state

  def cleanup(state) do
    {occupied, trails} =
      Enum.reduce(Map.fetch!(state, :players), {Map.fetch!(state, :occupied), Map.fetch!(state, :trails)}, fn
        {id, %{alive: false}}, {occupied, trails} ->
          {occupied, remaining} =
            retract(Map.get(trails, id, []), occupied, id, Map.fetch!(Map.fetch!(state, :config), :retract_speed))

          {occupied, Map.put(trails, id, remaining)}

        _, acc ->
          acc
      end)

    %{state | occupied: occupied, trails: trails}
  end

  defp prepend({x, y}, trail) when is_binary(trail), do: <<x::16, y::16, trail::binary>>
  defp prepend(position, trail), do: [position | trail]

  defp retract(trail, occupied, _id, 0), do: {occupied, trail}
  defp retract([], occupied, _id, _count), do: {occupied, []}
  defp retract(<<>>, occupied, _id, _count), do: {occupied, <<>>}

  defp retract(trail, occupied, id, count) do
    {remaining, cells} = retract_cells(trail, occupied, id, count, [])
    {Board.delete_many(occupied, cells), remaining}
  end

  defp retract_cells(trail, _occupied, _id, 0, cells), do: {trail, cells}
  defp retract_cells([], _occupied, _id, _count, cells), do: {[], cells}
  defp retract_cells(<<>>, _occupied, _id, _count, cells), do: {<<>>, cells}

  defp retract_cells(<<x::16, y::16, rest::binary>>, occupied, id, count, cells) do
    cells = if Board.get(occupied, {x, y}) == id, do: [{x, y} | cells], else: cells
    retract_cells(rest, occupied, id, count - 1, cells)
  end

  defp retract_cells([cell | rest], occupied, id, count, cells) do
    cells = if Board.get(occupied, cell) == id, do: [cell | cells], else: cells
    retract_cells(rest, occupied, id, count - 1, cells)
  end

  defp clear_blasts(occupied, _crashes, 0), do: occupied

  defp clear_blasts(occupied, [], _radius), do: occupied

  defp clear_blasts(occupied, crashes, radius) do
    offsets = :lists.seq(-radius, radius)

    cells =
      for {:crashed, _, {cx, cy}} <- crashes,
          dx <- offsets,
          dy <- offsets,
          dx * dx + dy * dy <= radius * radius,
          do: {cx + dx, cy + dy}

    Board.delete_many(occupied, cells)
  end

  @doc "Living players, ordered by stable ID."
  def living(%{players: players}) do
    for {_id, %{alive: true} = player} <- ordered(players), do: player
  end

  defp build_roster(roster, arena) when is_list(roster) and length(roster) >= 2 do
    build_players(roster, arena, %{})
  end

  defp build_roster(_, _arena), do: {:error, :invalid_players}

  defp build_players([], _arena, players), do: {:ok, players}

  defp build_players([entry | rest], arena, players) do
    with {:ok, player} <- Player.new(entry),
         true <- Arena.contains?(arena, Map.fetch!(player, :position)),
         false <- Map.has_key?(players, Map.fetch!(player, :id)),
         false <- Enum.any?(Map.values(players), &(Map.fetch!(&1, :position) == Map.fetch!(player, :position))) do
      build_players(rest, arena, Map.put(players, Map.fetch!(player, :id), player))
    else
      _ -> {:error, :invalid_players}
    end
  end

  defp validate_inputs(inputs, players) when is_map(inputs) do
    valid? =
      Enum.all?(inputs, fn {id, turn} ->
        match?(%{alive: true}, Map.get(players, id)) and (turn == :left or turn == :right)
      end)

    if valid?, do: :ok, else: {:error, :invalid_inputs}
  end

  defp validate_inputs(_, _), do: {:error, :invalid_inputs}
  defp outcome([]), do: :draw
  defp outcome([player]), do: {:winner, Map.fetch!(player, :id)}
  defp outcome(_), do: :running
  defp contraction_events(%{inset: inset}, %{inset: inset}), do: []
  defp contraction_events(_, arena), do: [{:arena_shrank, Map.fetch!(arena, :inset)}]

  defp ordered(map), do: :lists.keysort(1, Map.to_list(map))
end
