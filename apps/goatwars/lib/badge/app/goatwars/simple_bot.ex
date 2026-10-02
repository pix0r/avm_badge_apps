defmodule Badge.App.Goatwars.SimpleBot do
  @moduledoc "Straight cruising, clear turning lanes and short opponent-route interception."
  @behaviour Badge.App.Goatwars.Controller
  @compile :no_line_info
  alias Badge.App.Goatwars.{Arena, Board, Player}
  alias Badge.App.Goatwars.Bot.Profile

  @impl true
  def init(seed), do: init(seed, :intermediate)

  def init(seed, options) do
    seed = rem(abs(seed), 524_287)
    %{prediction_ticks: prediction, aggression: aggression} = Profile.new(options)
    %{seed: if(seed == 312_475, do: seed + 1, else: seed), profile: %{prediction_ticks: prediction, aggression: aggression}}
  end

  @doc "Prepares shared next-tick arena and opponent routes for a controller batch."
  def prepare(%{players: players, arena: arena, config: config, tick: tick, occupied: occupied}) do
    {players, Arena.advance(arena, config, tick + 1), occupied, routes(:maps.to_list(players), [])}
  end

  @impl true
  def choose(game, id, memory), do: choose_prepared(prepare(game), id, memory)

  def choose_prepared({players, arena, occupied, routes}, id, %{seed: previous, profile: profile} = memory) do
    %{position: origin, direction: heading} = Map.fetch!(players, id)
    seed = rem(previous * 251 + 13, 524_287)
    %{prediction_ticks: prediction, aggression: aggression} = profile
    horizon = min(prediction, 3)

    context = {heading, origin, arena, occupied, routes, id, horizon, aggression, seed}
    {best, cruising} = candidate(context, nil, 0, nil, false)
    best =
      if cruising and (elem(elem(best, 0), 2) >= aggression or not attack_near?(routes, id, origin, horizon)) do
        best
      else
        {best, cruising} = candidate(context, :left, 1, best, cruising)
        {best, _} = candidate(context, :right, 2, best, cruising)
        best
      end

    {if(best == nil, do: nil, else: elem(best, 1)), %{memory | seed: seed}}
  end

  defp candidate({heading, origin, arena, occupied, routes, id, horizon, aggression, seed}, turn, preference, best, cruising) do
    direction = Player.turn(heading, turn)
    position = Player.step(origin, direction)

    if free?(position, arena, occupied) do
      runway = runway(position, direction, arena, occupied, 2, 0)

      escape =
        if runway > 0 or free?(Player.step(position, Player.turn(direction, :left)), arena, occupied) or
             free?(Player.step(position, Player.turn(direction, :right)), arena, occupied),
           do: 1,
           else: 0

      {safe, attack} = opponents(routes, id, position, Player.step(position, direction), horizon, 1, 0)

      cruising = if turn == nil, do: safe == 1 and escape == 1, else: cruising

      runway =
        if turn != nil and not cruising,
          do:
            runway(
              position,
              direction,
              arena,
              occupied,
              max(Map.fetch!(arena, :right) - Map.fetch!(arena, :left), Map.fetch!(arena, :bottom) - Map.fetch!(arena, :top)),
              0
            ),
          else: runway

      score = {safe, escape, attack * aggression, if(turn == nil, do: 1, else: 0), runway, rem(seed + preference * 7, 3)}
      {if(best == nil or score > elem(best, 0), do: {score, turn}, else: best), cruising}
    else
      {best, cruising}
    end
  end

  defp attack_near?([], _id, _origin, _horizon), do: false

  defp attack_near?([{other, _next, {sx, sy}, {tx, ty}} | rest], id, {x, y} = origin, horizon) when other != id do
    (horizon >= 2 and abs(sx - x) + abs(sy - y) <= 1) or
      (horizon >= 3 and abs(tx - x) + abs(ty - y) <= 2) or attack_near?(rest, id, origin, horizon)
  end

  defp attack_near?([_ | rest], id, origin, horizon), do: attack_near?(rest, id, origin, horizon)

  defp routes([], routes), do: routes

  defp routes([{id, %{alive: true, position: origin, direction: heading}} | rest], routes) do
    next = Player.step(origin, heading)
    second = Player.step(next, heading)
    third = Player.step(second, heading)
    routes(rest, [{id, next, second, third} | routes])
  end

  defp routes([_ | rest], routes), do: routes(rest, routes)

  defp opponents([], _id, _position, _forward, _horizon, safe, attack), do: {safe, attack}

  defp opponents([{other, next, second, third} | rest], id, position, forward, horizon, safe, attack) when other != id do
    safe = if next == position, do: 0, else: safe
    intercept = if (horizon >= 2 and position == second) or (horizon >= 3 and (position == third or forward == third)), do: 1, else: 0
    opponents(rest, id, position, forward, horizon, safe, max(attack, intercept))
  end

  defp opponents([_ | rest], id, position, forward, horizon, safe, attack),
    do: opponents(rest, id, position, forward, horizon, safe, attack)

  defp runway(_position, _direction, _arena, _occupied, 0, count), do: count

  defp runway({x, y}, direction, %{left: left, right: right, top: top, bottom: bottom}, {width, height, bytes} = board, limit, count)
       when is_binary(bytes) and left >= 0 and top >= 0 and right < width and bottom < height and byte_size(bytes) >= width * height * 4 do
    {stride, available} =
      case direction do
        :north -> {-width * 4, y - top}
        :east -> {4, right - x}
        :south -> {width * 4, bottom - y}
        :west -> {-4, x - left}
      end

    scan_lane(board, (y * width + x) * 4 + stride, stride, min(limit, max(available, 0)), count)
  end

  defp runway(position, direction, arena, occupied, limit, count) do
    next = Player.step(position, direction)
    if free?(next, arena, occupied), do: runway(next, direction, arena, occupied, limit - 1, count + 1), else: count
  end

  defp scan_lane(_board, _offset, _stride, 0, count), do: count
  defp scan_lane({width, _height, bytes} = board, offset, stride, limit, count) do
    if :binary.at(bytes, offset) == 61 or Board.get(board, {rem(div(offset, 4), width), div(div(offset, 4), width)}) == nil,
      do: scan_lane(board, offset + stride, stride, limit - 1, count + 1),
      else: count
  end

  defp free?({x, y} = position, %{left: left, right: right, top: top, bottom: bottom}, occupied)
       when x >= left and x <= right and y >= top and y <= bottom,
       do: not Board.has?(occupied, position)

  defp free?(_, _, _), do: false
end
