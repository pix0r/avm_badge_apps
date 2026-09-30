defmodule Badge.App.Goatwars.ScoringTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Game, Match}

  test "survival earns 25 points; winner gets the declining bonus exactly once" do
    {:ok, game} =
      Game.new(%{width: 8, height: 8, points_per_tick: 25, bonus_start: 5000, bonus_decay: 15}, [
        %{id: 1, position: {0, 0}, direction: :west},
        %{id: 2, position: {4, 4}, direction: :east}
      ])

    match = Match.new(game, %{1 => :human, 2 => :human})
    done = Match.tick(match)
    assert done.scores == %{2 => 25}
    assert done.bonus == 4985
    assert done.awarded_bonus == {2, 4985}
    assert done.totals == %{2 => 5010}
    assert Match.tick(done) == done
  end

  test "a draw awards no bonus and the bonus cannot go negative" do
    {:ok, game} =
      Game.new(%{width: 8, height: 8, bonus_start: 10, bonus_decay: 15}, [
        %{id: 1, position: {0, 0}, direction: :west},
        %{id: 2, position: {7, 7}, direction: :east}
      ])

    done = Match.tick(Match.new(game, %{1 => :human, 2 => :human}))
    assert done.bonus == 0
    assert done.awarded_bonus == nil
    assert done.totals == %{}
  end
end
