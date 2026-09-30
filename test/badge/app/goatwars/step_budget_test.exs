defmodule Badge.App.Goatwars.StepBudgetTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.Game

  test "a tick without crashes does not traverse or rebuild the whole trail map" do
    {:ok, sparse} =
      Game.new(%{width: 100, height: 100, explosion_radius: 2, shrink_after: :never}, [
        %{id: 1, position: {4, 4}, direction: :east},
        %{id: 2, position: {8, 8}, direction: :west}
      ])

    occupied = for x <- 11..99, y <- 11..99, into: %{}, do: {{x, y}, 2}
    dense = %{sparse | occupied: Map.merge(occupied, sparse.occupied)}
    {sparse_work, _} = step(sparse)
    {dense_work, result} = step(dense)
    assert result.tick == 1
    assert result.status == :running
    assert dense_work <= sparse_work + 1000
  end

  test "a small explosion visits its blast area rather than the whole trail map" do
    {:ok, sparse} =
      Game.new(%{width: 100, height: 100, explosion_radius: 2, shrink_after: :never}, [
        %{id: 1, position: {4, 4}, direction: :east},
        %{id: 2, position: {8, 8}, direction: :west}
      ])

    sparse = %{sparse | occupied: Map.put(sparse.occupied, {5, 4}, 2)}
    occupied = for x <- 11..99, y <- 11..99, into: %{}, do: {{x, y}, 2}
    dense = %{sparse | occupied: Map.merge(occupied, sparse.occupied)}
    {sparse_work, _} = step(sparse)
    {dense_work, result} = step(dense)
    refute result.players[1].alive
    assert result.players[2].alive
    refute Map.has_key?(result.occupied, {5, 4})
    assert result.occupied[{50, 50}] == 2
    assert dense_work <= sparse_work + 1000
  end

  defp step(game) do
    {:reductions, before} = Process.info(self(), :reductions)
    {:ok, result, _events} = Game.step(game, %{})
    {:reductions, after_count} = Process.info(self(), :reductions)
    {after_count - before, result}
  end
end
