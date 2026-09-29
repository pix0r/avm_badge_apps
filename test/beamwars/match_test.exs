defmodule Badge.App.Beamwars.MatchTest do
  use ExUnit.Case, async: true

  alias Badge.App.Beamwars.{Bot, Game, Match}

  test "bots return turns or no command and avoid an immediate wall" do
    {:ok, game} =
      Game.new(
        %{width: 12, height: 10},
        [
          %{id: 1, position: {11, 4}, direction: :east},
          %{id: 2, position: {3, 7}, direction: :west}
        ]
      )

    {turn, _} = Bot.choose(game, 1, Bot.init(1, decision_delay: 0, reaction_ticks: 1))
    assert turn in [:left, :right]
    assert {^turn, _} = Bot.choose(game, 1, Bot.init(1, decision_delay: 0, reaction_ticks: 1))
  end

  test "four AI players finish reproducible headless rounds" do
    first = Match.demo(%{width: 32, height: 24}, 1)
    second = Match.demo(%{width: 32, height: 24}, 1)
    assert is_struct(first, Match)
    assert map_size(first.game.players) == 4
    result = Match.run(first, 32 * 24)
    assert result == Match.run(second, 32 * 24)
    refute result.game.status == :running
    assert result.game.tick <= 32 * 24
    assert length(result.replay) == result.game.tick
  end

  test "recorded commands replay the match without invoking controllers" do
    initial = Match.demo(%{width: 24, height: 18}, 2)
    result = Match.run(initial, 24 * 18)

    replayed =
      Enum.reduce(Enum.reverse(result.replay), initial.game, fn turns, game ->
        {:ok, next, _} = Game.step(game, turns)
        next
      end)

    assert replayed == result.game
  end

  test "human controllers consume one command then continue forward" do
    match = Match.demo(%{width: 32, height: 24}, 1)
    match = Match.control(match, 1, :human) |> Match.command(1, :left)
    start = match.game.players[1]
    next = Match.tick(match)
    assert next.pending == %{}
    assert next.game.players[1].direction != start.direction
    after_tick = Match.tick(next)
    assert after_tick.game.players[1].direction == next.game.players[1].direction
  end

  test "demo riders start at the four edge midpoints heading inward" do
    game = Match.demo(%{width: 32, height: 24}).game
    assert {game.players[1].position, game.players[1].direction} == {{16, 23}, :north}
    assert {game.players[2].position, game.players[2].direction} == {{16, 0}, :south}
    assert {game.players[3].position, game.players[3].direction} == {{0, 12}, :east}
    assert {game.players[4].position, game.players[4].direction} == {{31, 12}, :west}
  end

  test "survival points stop at death and do not change in terminal matches" do
    {:ok, game} =
      Game.new(%{width: 8, height: 8}, [
        %{id: 1, position: {0, 0}, direction: :west},
        %{id: 2, position: {4, 4}, direction: :east}
      ])

    match = %Match{game: game, controllers: %{1 => :human, 2 => :human}}
    result = Match.tick(match)
    assert result.scores == %{2 => 25}
    assert Match.tick(result).scores == result.scores
  end

  test "an aggressive pilot pursues an opponent after its thinking delay" do
    {:ok, game} =
      Game.new(%{width: 20, height: 16, shrink_after: :never}, [
        %{id: 1, position: {3, 5}, direction: :east},
        %{id: 2, position: {8, 10}, direction: :west}
      ])

    memory = Bot.init(1, decision_delay: 1, reaction_ticks: 3)
    {nil, thinking} = Bot.choose(game, 1, memory)
    assert thinking.pending == :right
    {:ok, next, _} = Game.step(game, %{})
    {:right, reacted} = Bot.choose(next, 1, thinking)
    {:ok, next, _} = Game.step(next, %{1 => :right})
    assert {nil, ^reacted} = Bot.choose(next, 1, reacted)
  end

  test "AI profiles expose tunable parameters and distinct difficulty presets" do
    beginner = Bot.init(1, :beginner)
    expert = Bot.init(1, :expert)
    assert is_struct(expert.profile, Badge.App.Beamwars.Bot.Profile)
    assert beginner.profile.reaction_ticks > expert.profile.reaction_ticks
    assert beginner.profile.search_limit < expert.profile.search_limit
    custom = Bot.init(1, reaction_ticks: 5, decision_delay: 2, aggression: 7, caution: 9)
    assert custom.profile.reaction_ticks == 5
    assert custom.profile.decision_delay == 2
    assert custom.profile.aggression == 7
    assert custom.profile.caution == 9
    assert_raise ArgumentError, fn -> Bot.init(1, reaction_ticks: 0) end
    assert_raise ArgumentError, fn -> Bot.init(1, imaginary_option: 1) end
  end

  test "each rider can use a separate configurable AI profile" do
    match = Match.demo(%{width: 32, height: 24}, 4, %{1 => :beginner, 2 => [aggression: 9]})
    {Bot, first} = match.controllers[1]
    {Bot, second} = match.controllers[2]
    assert first.profile.reaction_ticks == 5
    assert second.profile.aggression == 9
  end

  test "terminal matches are stable" do
    match = Match.demo(%{width: 12, height: 10}, 1) |> Match.run(120)
    assert Match.tick(match) == match
  end
end
