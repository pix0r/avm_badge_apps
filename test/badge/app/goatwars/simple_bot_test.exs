defmodule Badge.App.Goatwars.SimpleBotTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Arena, Board, Game, Player, SimpleBot}

  test "keeps heading when the next cell is clear" do
    game = game()
    memory = SimpleBot.init(1, :pro)
    {turn, updated} = SimpleBot.choose(game, 1, memory)
    assert turn == nil
    assert updated.profile == memory.profile
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

  test "lays a trail across an opponent's projected route instead of keeping heading" do
    game = %{game() | players: Map.put(game().players, 2, %{game().players[2] | position: {7, 6}})}
    game = %{game | occupied: %{{4, 4} => 1, {7, 6} => 2}}

    for seed <- 1..16 do
      assert {:right, _} = SimpleBot.choose(game, 1, SimpleBot.init(seed, :pro))
    end
  end

  test "avoids a clear cell with no onward escape before pursuing or jittering" do
    game = game()
    occupied = Map.merge(game.occupied, %{{6, 4} => 2, {5, 3} => 2, {5, 5} => 2})
    game = %{game | occupied: occupied}

    for seed <- 1..32 do
      {turn, _} = SimpleBot.choose(game, 1, SimpleBot.init(seed, :pro))
      assert turn == :left or turn == :right
    end
  end

  test "avoids an opponent's next head when another move is safe" do
    game = game()
    game = %{game | players: Map.put(game.players, 2, %{game.players[2] | position: {6, 4}}), occupied: %{{4, 4} => 1, {6, 4} => 2}}

    for seed <- 1..32 do
      {turn, _} = SimpleBot.choose(game, 1, SimpleBot.init(seed, :pro))
      assert turn == :left or turn == :right
    end
  end

  test "seeded choices vary on comparable safe routes and remain reproducible" do
    game = game()
    game = %{game | players: Map.put(game.players, 2, %{game.players[2] | alive: false})}

    turns =
      for seed <- 1..64 do
        memory = SimpleBot.init(seed, aggression: 0)
        decision = SimpleBot.choose(game, 1, memory)
        assert decision == SimpleBot.choose(game, 1, memory)
        elem(decision, 0)
      end

    assert MapSet.new(turns) == MapSet.new([nil, :left, :right])
  end

  test "each decision advances a small seed without changing custom profiles" do
    game = game()
    memory = SimpleBot.init(134_217_726, aggression: 3, prediction_ticks: 4)
    {_, next} = SimpleBot.choose(game, 1, memory)
    {_, later} = SimpleBot.choose(game, 1, next)
    assert next.seed != memory.seed
    assert later.seed != next.seed
    assert next.seed >= 0 and next.seed < 134_217_728
    assert later.seed >= 0 and later.seed < 134_217_728
    assert next.profile == memory.profile
    assert later.profile == memory.profile
    fixed = SimpleBot.init(312_475)
    {_, advanced} = SimpleBot.choose(game, 1, fixed)
    assert advanced.seed != fixed.seed
  end

  test "seeded safety and attacks agree for map and bitmap boards" do
    game = game()
    game = %{game | occupied: Map.merge(game.occupied, %{{5, 4} => 2, {4, 3} => 3})}
    bitmap = Game.compact(game)

    for seed <- 1..32 do
      memory = SimpleBot.init(seed)
      assert SimpleBot.choose(bitmap, 1, memory) == SimpleBot.choose(game, 1, memory)
      {turn, _} = SimpleBot.choose(game, 1, memory)
      next = Player.move(game.players[1], turn)
      assert Arena.contains?(game.arena, next.position)
      refute Board.has?(game.occupied, next.position)
    end
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
