defmodule Badge.App.Goatwars.StepBudgetTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Game, Page, State}

  test "public states without trail entries can step and clean up" do
    {:ok, game} =
      Game.new(%{width: 20, height: 20, shrink_after: :never, retract_speed: 8}, [
        %{id: 1, position: {4, 4}, direction: :east},
        %{id: 2, position: {8, 8}, direction: :west}
      ])

    state = State.new(Map.delete(game, :trails))
    assert {:ok, advanced, []} = Game.step(state, %{})
    assert advanced.trails[1] == [{5, 4}]
    assert advanced.trails[2] == [{7, 8}]
    dead = %{state | players: Map.put(state.players, 1, %{state.players[1] | alive: false})}
    assert Game.cleanup(dead) == dead
  end

  test "a four-goat frame stays within a small traversal work budget" do
    state = Enum.reduce(0..3, Page.init(countdown_ms: 0), &Page.advance(&2, &1 * 100))
    {:reductions, before} = Process.info(self(), :reductions)
    Enum.each(1..1000, fn _ -> Page.render(Page.advance(state, 400)) end)
    {:reductions, after_count} = Process.info(self(), :reductions)
    assert div(after_count - before, 1000) <= 600
  end

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
