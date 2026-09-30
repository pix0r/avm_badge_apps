defmodule Badge.App.Goatwars.GameTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.Game

  defp players do
    [%{id: 1, position: {1, 2}, direction: :east}, %{id: 2, position: {5, 2}, direction: :west}]
  end

  test "configurable arena and initial heads are occupied" do
    assert {:ok, game} = Game.new(%{width: 7, height: 5}, players())
    assert game.tick == 0
    assert game.status == :running
    assert game.occupied == %{{1, 2} => 1, {5, 2} => 2}
  end

  test "rejects invalid arenas, rosters and spawns" do
    for rules <- [%{width: 0, height: 5}, %{width: 5}, %{width: 5.5, height: 5}] do
      assert {:error, :invalid_rules} = Game.new(rules, players())
    end

    for roster <- [
          [],
          [hd(players())],
          [hd(players()), hd(players())],
          [%{id: 1, position: {-1, 0}, direction: :east}, List.last(players())]
        ] do
      assert {:error, :invalid_players} = Game.new(%{width: 7, height: 5}, roster)
    end
  end

  test "one step moves everyone and retains their trails" do
    {:ok, game} = Game.new(%{width: 7, height: 5}, players())
    assert {:ok, next, []} = Game.step(game, %{})
    assert next.players[1].position == {2, 2}
    assert next.players[2].position == {4, 2}
    assert map_size(next.occupied) == 4
    assert next.tick == 1
    assert game.tick == 0
  end

  test "turns are relative to each heading" do
    {:ok, game} = Game.new(%{width: 7, height: 5}, players())
    {:ok, next, []} = Game.step(game, %{1 => :left, 2 => :right})
    assert next.players[1].position == {1, 1}
    assert next.players[2].position == {5, 1}
    assert next.players[1].direction == :north
    assert next.players[2].direction == :north
  end

  test "head-on collision is a draw regardless of roster order" do
    for roster <- [players(), Enum.reverse(players())] do
      {:ok, game} = Game.new(%{width: 7, height: 5}, roster)
      {:ok, game, []} = Game.step(game, %{})
      {:ok, done, events} = Game.step(game, %{})
      assert done.status == :draw
      assert events == [{:crashed, 1, {3, 2}}, {:crashed, 2, {3, 2}}]
      assert map_size(done.occupied) == 4
      assert {:ok, ^done, []} = Game.step(done, %{})
    end
  end

  test "head swaps collide with existing heads" do
    roster = [
      %{id: 1, position: {1, 1}, direction: :east},
      %{id: 2, position: {2, 1}, direction: :west}
    ]

    {:ok, game} = Game.new(%{width: 4, height: 4}, roster)
    {:ok, done, _} = Game.step(game, %{})
    assert done.status == :draw
  end

  test "wall crash leaves a winner and preserves the dead player's trail" do
    roster = [%{id: 1, position: {0, 0}, direction: :west}, List.last(players())]
    {:ok, game} = Game.new(%{width: 7, height: 5}, roster)
    {:ok, done, [{:crashed, 1, {-1, 0}}]} = Game.step(game, %{})
    assert done.status == {:winner, 2}
    refute done.players[1].alive
    assert done.occupied[{0, 0}] == 1
  end

  test "three players can continue after one dies" do
    roster = [%{id: 3, position: {0, 0}, direction: :west} | players()]
    {:ok, game} = Game.new(%{width: 7, height: 5}, roster)
    {:ok, next, _} = Game.step(game, %{})
    assert next.status == :running
    assert {:error, :invalid_inputs} = Game.step(next, %{3 => :left})
  end

  test "invalid commands are rejected without advancing" do
    {:ok, game} = Game.new(%{width: 7, height: 5}, players())

    for inputs <- [%{9 => :left}, %{1 => :reverse}, %{1 => :straight}, [:left]] do
      assert {:error, :invalid_inputs} = Game.step(game, inputs)
    end
  end

  test "a turn lasts one tick; omission keeps the new heading" do
    {:ok, game} = Game.new(%{width: 7, height: 5}, players())
    {:ok, turned, []} = Game.step(game, %{1 => :left})
    {:ok, next, []} = Game.step(turned, %{})
    assert next.players[1].position == {1, 0}
    assert next.players[1].direction == :north
  end

  test "controller metadata is not part of game state" do
    roster = Enum.map(players(), &Map.put(&1, :controller, :human))
    {:ok, game} = Game.new(%{width: 7, height: 5}, roster)
    refute Map.has_key?(game.players[1], :controller)
  end

  test "a bike dies when its path loops back onto its own permanent trail" do
    {:ok, game} =
      Game.new(
        %{width: 20, height: 20, shrink_after: :never},
        [
          %{id: 1, position: {4, 4}, direction: :east},
          %{id: 2, position: {15, 15}, direction: :west}
        ]
      )

    game =
      Enum.reduce(1..3, game, fn _, state ->
        {:ok, next, []} = Game.step(state, %{1 => :right})
        next
      end)

    {:ok, done, [{:crashed, 1, {4, 4}}]} = Game.step(game, %{1 => :right})
    assert done.status == {:winner, 2}
  end

  test "an opponent's old trail remains lethal after its head passes" do
    {:ok, game} =
      Game.new(
        %{width: 12, height: 12},
        [
          %{id: 1, position: {2, 3}, direction: :east},
          %{id: 2, position: {4, 2}, direction: :south}
        ]
      )

    {:ok, game, []} = Game.step(game, %{1 => :right})
    {:ok, game, []} = Game.step(game, %{1 => :left})
    {:ok, done, [{:crashed, 1, {4, 4}}]} = Game.step(game, %{})
    assert done.status == {:winner, 2}
  end
end
