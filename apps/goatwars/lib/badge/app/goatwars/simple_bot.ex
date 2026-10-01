defmodule Badge.App.Goatwars.SimpleBot do
  @moduledoc "Seeded local escape checks and short opponent-route interception."
  @behaviour Badge.App.Goatwars.Controller
  alias Badge.App.Goatwars.{Arena, Board, Player}
  alias Badge.App.Goatwars.Bot.Profile

  @impl true
  def init(seed), do: init(seed, :intermediate)

  def init(seed, options) do
    seed = rem(abs(seed), 524_287)
    %{seed: if(seed == 312_475, do: seed + 1, else: seed), profile: Profile.new(options)}
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

    best =
      Enum.reduce([{nil, 0}, {:left, 1}, {:right, 2}], nil, fn {turn, preference}, best ->
        direction = Player.turn(heading, turn)
        position = Player.step(origin, direction)

        if free?(position, arena, occupied) do
          runway = runway(position, direction, arena, occupied)

          escape =
            if runway > 0 or free?(Player.step(position, Player.turn(direction, :left)), arena, occupied) or
                 free?(Player.step(position, Player.turn(direction, :right)), arena, occupied),
               do: 1,
               else: 0

          {safe, attack} = opponents(routes, id, position, Player.step(position, direction), horizon, 1, 0)

          jitter =
            if rem(seed, 8) == 0 and rem(div(seed, 8), 3) == preference, do: 7, else: rem(seed + preference * 7, 3)

          value = attack * aggression + jitter + if(turn == nil, do: 2, else: 0)
          score = {safe, escape, runway, value}
          if best == nil or score > elem(best, 0), do: {score, turn}, else: best
        else
          best
        end
      end)

    {if(best == nil, do: nil, else: elem(best, 1)), %{memory | seed: seed}}
  end

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
    first = if horizon >= 1, do: proximity(position, next), else: 0
    second = if horizon >= 2, do: proximity(position, second) + if(position == second, do: 16, else: 0), else: 0
    third = if horizon >= 3, do: proximity(position, third) + if(position == third or forward == third, do: 16, else: 0), else: 0
    opponents(rest, id, position, forward, horizon, safe, max(attack, max(first, max(second, third))))
  end

  defp opponents([_ | rest], id, position, forward, horizon, safe, attack),
    do: opponents(rest, id, position, forward, horizon, safe, attack)

  defp proximity({x, y}, {tx, ty}), do: max(0, 12 - abs(x - tx) - abs(y - ty))

  defp runway(position, direction, arena, occupied) do
    next = Player.step(position, direction)
    if free?(next, arena, occupied), do: if(free?(Player.step(next, direction), arena, occupied), do: 2, else: 1), else: 0
  end

  defp free?({x, y} = position, %{left: left, right: right, top: top, bottom: bottom}, occupied)
       when x >= left and x <= right and y >= top and y <= bottom,
       do: not Board.has?(occupied, position)

  defp free?(_, _, _), do: false
end
