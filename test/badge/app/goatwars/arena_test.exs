defmodule Badge.App.Goatwars.ArenaTest do
  use ExUnit.Case, async: true

  alias Badge.App.Goatwars.{Arena, Game}

  defp roster do
    [%{id: 1, position: {2, 3}, direction: :east}, %{id: 2, position: {6, 5}, direction: :west}]
  end

  test "the core uses plain-map state, config, arena and players" do
    {:ok, game} = Game.new(%{width: 9, height: 9}, roster())
    refute is_struct(game)
    refute is_struct(game.config)
    refute is_struct(game.arena)
    refute is_struct(game.players[1])
    assert game.config.shrink_after == 32
  end

  test "warning precedes the first contraction and each slow subsequent contraction" do
    {:ok, game} =
      Game.new(
        %{width: 9, height: 9, shrink_after: 10, warning_ticks: 3, shrink_every: 6},
        roster()
      )

    refute Arena.warning?(game.arena, game.config, 6)
    assert Arena.warning?(game.arena, game.config, 7)
    assert Arena.warning?(game.arena, game.config, 9)
    first = Arena.advance(game.arena, game.config, 10)
    assert first.inset == 1
    refute Arena.contains?(first, {0, 4})
    assert Arena.contains?(first, {1, 4})
    refute Arena.warning?(first, game.config, 12)
    assert Arena.warning?(first, game.config, 13)
    assert Arena.advance(first, game.config, 15).inset == 1
    assert Arena.advance(first, game.config, 16).inset == 2
  end

  test "a contracting wall eliminates a bike on the swept ring even if it turns inward" do
    roster = [
      %{id: 1, position: {0, 4}, direction: :north},
      %{id: 2, position: {5, 5}, direction: :east}
    ]

    {:ok, game} = Game.new(%{width: 9, height: 9, shrink_after: 1}, roster)
    {:ok, next, events} = Game.step(game, %{1 => :right})
    assert next.arena.inset == 1
    assert next.status == {:winner, 2}
    assert {:arena_shrank, 1} in events
    assert {:crashed, 1, {1, 4}} in events
  end

  test "a move onto a newly removed ring crashes and trails stay occupied" do
    roster = [
      %{id: 1, position: {1, 4}, direction: :west},
      %{id: 2, position: {5, 5}, direction: :east}
    ]

    {:ok, game} = Game.new(%{width: 9, height: 9, shrink_after: 1}, roster)
    {:ok, next, _} = Game.step(game, %{})
    assert next.status == {:winner, 2}
    assert next.occupied[{1, 4}] == 1
  end

  test "contraction can be disabled and stops before bounds invert" do
    {:ok, game} = Game.new(%{width: 9, height: 9, shrink_after: :never}, roster())
    assert Arena.advance(game.arena, game.config, 1000) == game.arena
    refute Arena.warning?(game.arena, game.config, 1000)

    {:ok, small} =
      Game.new(
        %{width: 3, height: 3, shrink_after: 1, shrink_every: 1, warning_ticks: 0},
        [
          %{id: 1, position: {0, 0}, direction: :east},
          %{id: 2, position: {2, 2}, direction: :west}
        ]
      )

    arena = Arena.advance(small.arena, small.config, 100)
    assert arena.inset == 1
    assert arena.next_shrink_tick == nil
    assert Arena.contains?(arena, {1, 1})
  end

  test "invalid timing parameters and unknown configuration keys fail clearly" do
    for options <- [
          %{step_ms: 0},
          %{shrink_every: 0},
          %{warning_ticks: -1},
          %{shrink_after: -1},
          %{widht: 9}
        ] do
      rules = Map.merge(%{width: 9, height: 9}, options)
      assert {:error, :invalid_rules} = Game.new(rules, roster())
    end
  end
end
