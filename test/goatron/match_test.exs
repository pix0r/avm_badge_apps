defmodule Badge.App.Goatron.MatchTest do
  use ExUnit.Case, async: true

  alias Badge.App.Goatron.{Bot, Game, Match}

  test "bots return turns or no command and avoid an immediate wall" do
    {:ok, game} =
      Game.new(
        %{width: 12, height: 10},
        [%{id: 1, position: {11, 4}, direction: :east}, %{id: 2, position: {3, 7}, direction: :west}]
      )

    {turn, _} = Bot.choose(game, 1, Bot.init(1))
    assert turn in [:left, :right]
    assert {^turn, _} = Bot.choose(game, 1, Bot.init(1))
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

  test "terminal matches are stable" do
    match = Match.demo(%{width: 12, height: 10}, 1) |> Match.run(120)
    assert Match.tick(match) == match
  end
end
