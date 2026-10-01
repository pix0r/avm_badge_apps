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

  @impl true
  def choose(%{players: players, arena: arena, config: config, tick: tick, occupied: occupied}, id, memory) do
    player = Map.fetch!(players, id)
    arena = Arena.advance(arena, config, tick + 1)
    seed = rem(Map.fetch!(memory, :seed) * 251 + 13, 524_287)
    profile = Map.fetch!(memory, :profile)
    others = :maps.to_list(players)

    best =
      Enum.reduce([{nil, 0}, {:left, 1}, {:right, 2}], nil, fn {turn, preference}, best ->
        %{position: position, direction: direction} = Player.move(player, turn)

        if free?(position, arena, occupied) do
          runway = runway(position, direction, arena, occupied, 2)

          escape =
            if runway > 0 or free?(Player.step(position, Player.turn(direction, :left)), arena, occupied) or
                 free?(Player.step(position, Player.turn(direction, :right)), arena, occupied),
               do: 1,
               else: 0

          {safe, attack} = opponents(others, id, position, direction, min(Map.fetch!(profile, :prediction_ticks), 3), 1, 0)

          jitter =
            if rem(seed, 8) == 0 and rem(div(seed, 8), 3) == preference, do: 7, else: rem(seed + preference * 7, 3)

          value = attack * Map.fetch!(profile, :aggression) + jitter + if(turn == nil, do: 2, else: 0)
          score = {safe, escape, runway, value}
          if best == nil or score > elem(best, 0), do: {score, turn}, else: best
        else
          best
        end
      end)

    {if(best == nil, do: nil, else: elem(best, 1)), %{memory | seed: seed}}
  end

  defp opponents([], _id, _position, _direction, _horizon, safe, attack), do: {safe, attack}

  defp opponents([{other, %{alive: true, position: origin, direction: heading}} | rest], id, position, direction, horizon, safe, attack)
       when other != id do
    safe = if Player.step(origin, heading) == position, do: 0, else: safe
    attack = max(attack, forecast(origin, heading, position, direction, 1, horizon, 0))
    opponents(rest, id, position, direction, horizon, safe, attack)
  end

  defp opponents([_ | rest], id, position, direction, horizon, safe, attack),
    do: opponents(rest, id, position, direction, horizon, safe, attack)

  defp forecast(_origin, _heading, _position, _direction, time, horizon, value) when time > horizon, do: value

  defp forecast(origin, heading, {x, y} = position, direction, time, horizon, value) do
    {tx, ty} = target = Player.step(origin, heading)
    intercept = if ahead(position, target, direction) < time - 1, do: 16, else: 0
    value = max(value, max(0, 12 - abs(x - tx) - abs(y - ty)) + intercept)
    forecast(target, heading, position, direction, time + 1, horizon, value)
  end

  defp ahead({x, y}, {tx, y}, :east) when tx >= x, do: tx - x
  defp ahead({x, y}, {tx, y}, :west) when tx <= x, do: x - tx
  defp ahead({x, y}, {x, ty}, :south) when ty >= y, do: ty - y
  defp ahead({x, y}, {x, ty}, :north) when ty <= y, do: y - ty
  defp ahead(_, _, _), do: 128

  defp runway(_position, _direction, _arena, _occupied, 0), do: 0

  defp runway(position, direction, arena, occupied, remaining) do
    next = Player.step(position, direction)
    if free?(next, arena, occupied), do: 1 + runway(next, direction, arena, occupied, remaining - 1), else: 0
  end

  defp free?(position, arena, occupied), do: Arena.contains?(arena, position) and not Board.has?(occupied, position)
end
