defmodule Badge.App.Goatwars.SimpleBot do
  @moduledoc "Local obstacle avoidance: keep heading, otherwise try each side once."
  @behaviour Badge.App.Goatwars.Controller
  alias Badge.App.Goatwars.{Arena, Board, Player}
  alias Badge.App.Goatwars.Bot.Profile

  @impl true
  def init(seed), do: init(seed, :intermediate)

  def init(seed, options), do: %{seed: seed, profile: Profile.new(options)}

  @impl true
  def choose(%{players: players, arena: arena, config: config, tick: tick, occupied: occupied}, id, memory) do
    player = Map.fetch!(players, id)
    arena = Arena.advance(arena, config, tick + 1)
    first = if rem(Map.fetch!(memory, :seed), 2) == 0, do: :left, else: :right
    second = if first == :left, do: :right, else: :left
    {turn([nil, first, second], player, arena, occupied), memory}
  end

  defp turn([], _player, _arena, _occupied), do: nil

  defp turn([choice | rest], player, arena, occupied) do
    %{position: position} = Player.move(player, choice)

    if Arena.contains?(arena, position) and not Board.has?(occupied, position),
      do: choice,
      else: turn(rest, player, arena, occupied)
  end
end
