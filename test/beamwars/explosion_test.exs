defmodule Badge.App.Beamwars.ExplosionTest do
  use ExUnit.Case, async: true
  alias Badge.App.Beamwars.Game

  defp arena(options) do
    rules = Map.merge(%{width: 20, height: 16, shrink_after: :never, retract_speed: 0}, options)

    Game.new(rules, [
      %{id: 1, position: {5, 5}, direction: :east},
      %{id: 2, position: {12, 12}, direction: :west},
      %{id: 3, position: {15, 3}, direction: :west}
    ])
  end

  test "an explosion clears nearby trails immediately, but preserves distant cells" do
    {:ok, game} = arena(%{explosion_radius: 2})
    occupied = Map.merge(game.occupied, %{{6, 5} => 2, {6, 6} => 2, {8, 5} => 3, {9, 5} => 3})
    game = %{game | occupied: occupied}
    {:ok, next, events} = Game.step(game, %{})
    assert {:crashed, 1, {6, 5}} in events
    refute next.players[1].alive
    refute Map.has_key?(next.occupied, {6, 5})
    refute Map.has_key?(next.occupied, {6, 6})
    refute Map.has_key?(next.occupied, {8, 5})
    assert next.occupied[{9, 5}] == 3
    assert next.occupied[next.players[2].position] == 2
    assert next.status == :running
  end

  test "cleared trail cells can be crossed on a later tick" do
    {:ok, game} =
      Game.new(%{width: 20, height: 16, explosion_radius: 2, retract_speed: 0}, [
        %{id: 1, position: {5, 5}, direction: :east},
        %{id: 2, position: {6, 8}, direction: :north},
        %{id: 3, position: {15, 3}, direction: :west}
      ])

    game = %{game | occupied: Map.merge(game.occupied, %{{6, 5} => 3, {6, 6} => 3})}
    {:ok, next, _} = Game.step(game, %{})
    {:ok, next, _} = Game.step(next, %{})
    assert next.players[2].alive
    assert next.players[2].position == {6, 6}
  end

  test "collision resolution uses the old board before any simultaneous blast" do
    {:ok, game} =
      Game.new(%{width: 20, height: 16, explosion_radius: 3, retract_speed: 0}, [
        %{id: 1, position: {5, 5}, direction: :east},
        %{id: 2, position: {6, 7}, direction: :north},
        %{id: 3, position: {15, 3}, direction: :west}
      ])

    game = %{game | occupied: Map.merge(game.occupied, %{{6, 5} => 3, {6, 6} => 3})}
    {:ok, next, _} = Game.step(game, %{})
    refute next.players[1].alive
    refute next.players[2].alive
    assert next.status == {:winner, 3}
  end

  test "retraction removes a dead beam from the head backward at a configured speed" do
    {:ok, game} =
      Game.new(%{width: 20, height: 16, explosion_radius: 0, retract_speed: 1}, [
        %{id: 1, position: {1, 1}, direction: :east},
        %{id: 2, position: {14, 12}, direction: :west},
        %{id: 3, position: {15, 3}, direction: :west}
      ])

    {:ok, game, _} = Game.step(game, %{})
    {:ok, game, _} = Game.step(game, %{})
    game = %{game | occupied: Map.put(game.occupied, {4, 1}, 3)}
    {:ok, next, _} = Game.step(game, %{})
    refute Map.has_key?(next.occupied, {3, 1})
    assert next.occupied[{2, 1}] == 1
    {:ok, next, _} = Game.step(next, %{})
    refute Map.has_key?(next.occupied, {2, 1})
    assert next.occupied[{1, 1}] == 1
  end
end
