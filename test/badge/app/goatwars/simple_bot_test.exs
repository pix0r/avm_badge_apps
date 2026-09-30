defmodule Badge.App.Goatwars.SimpleBotTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Game, Player, SimpleBot}

  test "keeps heading when the next cell is clear" do
    game = game()
    memory = SimpleBot.init(1, :pro)
    assert SimpleBot.choose(game, 1, memory) == {nil, memory}
  end

  test "turns around a trail and chooses the other side if its preferred side is blocked" do
    game = game()
    memory = SimpleBot.init(1, :pro)
    game = %{game | occupied: Map.put(game.occupied, {5, 4}, 2)}
    {turn, _} = SimpleBot.choose(game, 1, memory)
    assert turn == :left or turn == :right
    blocked = Player.move(game.players[1], turn).position
    game = %{game | occupied: Map.put(game.occupied, blocked, 2)}
    {other, _} = SimpleBot.choose(game, 1, memory)
    assert other != turn and (other == :left or other == :right)
  end

  test "avoids the ring that contracts before the next move" do
    game = game()

    game = %{
      game
      | players: Map.put(game.players, 1, %{game.players[1] | position: {1, 4}, direction: :west}),
        config: %{game.config | shrink_after: 1},
        arena: %{game.arena | next_shrink_tick: 1}
    }

    {turn, _} = SimpleBot.choose(game, 1, SimpleBot.init(2))
    assert turn == :left or turn == :right
  end

  test "decision work does not grow with the trail map" do
    sparse = game()
    occupied = for x <- 0..99, y <- 0..99, x > 10 and y > 10, into: %{}, do: {{x, y}, 2}
    dense = %{sparse | occupied: Map.merge(occupied, sparse.occupied)}
    memory = SimpleBot.init(1, :pro)
    assert reductions(dense, memory) <= reductions(sparse, memory) + 300
  end

  defp game do
    {:ok, game} =
      Game.new(%{width: 100, height: 100, shrink_after: :never}, [
        %{id: 1, position: {4, 4}, direction: :east},
        %{id: 2, position: {8, 8}, direction: :west}
      ])

    game
  end

  defp reductions(game, memory) do
    {:reductions, before} = Process.info(self(), :reductions)
    SimpleBot.choose(game, 1, memory)
    {:reductions, after_count} = Process.info(self(), :reductions)
    after_count - before
  end
end
