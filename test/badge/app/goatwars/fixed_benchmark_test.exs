defmodule Badge.App.Goatwars.FixedBenchmarkTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Board, Page}
  Code.require_file("scripts/goatwars_benchmark.ex", File.cwd!())

  test "fixed performance fixtures use identical head and obstacle inputs" do
    for {width, height, heads, fronts} <- [
          {23, 23, [{5, 5}, {17, 5}, {5, 17}, {17, 17}], [{6, 5}, {16, 5}, {5, 16}, {17, 18}]},
          {78, 46, [{19, 11}, {58, 11}, {19, 34}, {58, 34}], [{20, 11}, {57, 11}, {19, 33}, {58, 35}]}
        ],
        blocked <- [false, true] do
      state = GoatwarsBenchmark.fixed_state(width, height, blocked)
      game = state.match.game
      assert game.tick == 0
      assert game.config.width == width and game.config.height == height
      assert Enum.map(1..4, &game.players[&1].position) == heads
      for front <- fronts, do: assert(Board.has?(game.occupied, front) == blocked)
      advanced = Page.advance(state, 0)
      assert advanced.match.game.tick == 1
      assert Enum.all?(advanced.match.game.players, fn {_, player} -> player.alive end)
    end
  end
end
