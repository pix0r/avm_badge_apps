defmodule Badge.App.Goatwars.Game do
  @moduledoc """
  Pure, simultaneous lightcycle rules. Left/right commands apply for one tick;
  omission preserves heading. Explosions and retraction clear trails when enabled.
  Contraction removes the outer ring before movement and sweeps bikes on it.
  """
  @compile :no_line_info
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

  defp advance(%{tick: tick, arena: previous_arena, config: config, players: players, occupied: occupied, trails: trails} = state, inputs) do
    tick = tick + 1
    arena = Arena.advance(previous_arena, config, tick)
    {proposals, destinations} = proposals(living(state), inputs, [], %{})

    {players, occupied, trails, crashes, heads} =
      resolve_all(:lists.reverse(proposals), state, arena, destinations, players, occupied, trails, [], [])

    occupied = clear_blasts(occupied, crashes, Map.fetch!(config, :explosion_radius))
    occupied = if crashes == [], do: occupied, else: restore_heads(heads, occupied)
    next = cleanup(%{state | tick: tick, arena: arena, players: players, occupied: occupied, trails: trails, status: outcome_heads(heads)})
    {:ok, next, contraction_events(previous_arena, arena) ++ :lists.reverse(crashes)}
  end

  defp proposals([], _inputs, proposals, destinations), do: {proposals, destinations}

  defp proposals([%{id: id} = player | rest], inputs, proposals, destinations) do
    %{position: position} = proposed = Player.move(player, Map.get(inputs, id))

    count =
      case destinations do
        %{^position => count} -> count
        _ -> 0
      end

    proposals(rest, inputs, [{id, proposed} | proposals], Map.put(destinations, position, count + 1))
  end

  defp resolve_all([], _state, _arena, _destinations, players, occupied, trails, crashes, heads),
    do: {players, occupied, trails, crashes, heads}

  defp resolve_all(
         [{id, %{position: position, direction: direction} = proposed} | rest],
         %{players: originals, occupied: old_board} = state,
         arena,
         destinations,
         players,
         occupied,
         trails,
         crashes,
         heads
       ) do
    %{position: origin} = original = Map.fetch!(originals, id)

    collision =
      not Arena.contains?(arena, origin) or not Arena.contains?(arena, position) or
        Board.has?(old_board, position) or Map.fetch!(destinations, position) > 1

    if collision do
      dead = %{original | alive: false, direction: direction}

      resolve_all(
        rest,
        state,
        arena,
        destinations,
        Map.put(players, id, dead),
        occupied,
        trails,
        [{:crashed, id, position} | crashes],
        heads
      )
    else
      trail = prepend(position, Map.get(trails, id, []))

      resolve_all(
        rest,
        state,
        arena,
        destinations,
        Map.put(players, id, proposed),
        Board.put(occupied, position, id),
        Map.put(trails, id, trail),
        crashes,
        [{id, position} | heads]
      )
    end
  end

  defp restore_heads([], occupied), do: occupied
  defp restore_heads([{id, position} | rest], occupied), do: restore_heads(rest, Board.put(occupied, position, id))
  defp outcome_heads([]), do: :draw
  defp outcome_heads([{id, _}]), do: {:winner, id}
  defp outcome_heads(_), do: :running

  @doc "Retracts dead beams by one configured chunk without advancing the round clock."
  def cleanup(%{config: %{retract_speed: 0}} = state), do: state

  def cleanup(%{players: players, occupied: occupied, trails: trails, config: %{retract_speed: speed}} = state) do
    {occupied, trails} = cleanup_players(:maps.to_list(players), occupied, trails, speed)

    if occupied === Map.fetch!(state, :occupied) and trails === Map.fetch!(state, :trails),
      do: state,
      else: %{state | occupied: occupied, trails: trails}
  end

  defp cleanup_players([], occupied, trails, _speed), do: {occupied, trails}

  defp cleanup_players([{id, %{alive: false}} | rest], occupied, trails, speed) do
    case Map.get(trails, id, []) do
      <<>> ->
        cleanup_players(rest, occupied, trails, speed)

      [] ->
        cleanup_players(rest, occupied, trails, speed)

      trail ->
        {occupied, remaining} = retract(trail, occupied, id, speed)
        cleanup_players(rest, occupied, Map.put(trails, id, remaining), speed)
    end
  end

  defp cleanup_players([_ | rest], occupied, trails, speed), do: cleanup_players(rest, occupied, trails, speed)

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
  def living(%{players: players}), do: living_players(ordered(players))
  defp living_players([]), do: []
  defp living_players([{_, %{alive: true} = player} | rest]), do: [player | living_players(rest)]
  defp living_players([_ | rest]), do: living_players(rest)

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

  defp validate_inputs(inputs, _players) when is_map(inputs) and map_size(inputs) == 0, do: :ok

  defp validate_inputs(inputs, players) when is_map(inputs) do
    valid? =
      Enum.all?(inputs, fn {id, turn} ->
        match?(%{alive: true}, Map.get(players, id)) and (turn == :left or turn == :right)
      end)

    if valid?, do: :ok, else: {:error, :invalid_inputs}
  end

  defp validate_inputs(_, _), do: {:error, :invalid_inputs}
  defp contraction_events(%{inset: inset}, %{inset: inset}), do: []
  defp contraction_events(_, arena), do: [{:arena_shrank, Map.fetch!(arena, :inset)}]

  defp ordered(map), do: :lists.keysort(1, Map.to_list(map))
end
