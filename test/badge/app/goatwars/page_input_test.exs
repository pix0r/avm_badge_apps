defmodule Badge.App.Goatwars.PageInputTest do
  use ExUnit.Case
  alias Badge.App.Goatwars.{Game, Match, Page}

  test "steering avoids a redraw and applies once at the scheduled step" do
    state = Page.init(countdown_ms: 0) |> Page.advance(1000)
    items = Page.render(state)
    assert Page.handle_key({:move, :left}, state) == :ignore
    assert Page.render(state) == items
    assert Page.advance(state, state.due_at - 1) == state
    next = Page.advance(state, state.due_at)
    assert next.match.game.tick == state.match.game.tick + 1
    assert next.match.game.players[1].direction == :west
    assert next.match.pending == %{}
    assert Page.advance(next, next.due_at).match.game.players[1].direction == :west
  end

  test "the latest turn wins without buffering repeated turns" do
    state = Page.init(countdown_ms: 0)
    for _ <- 1..100, do: assert(Page.handle_key({:move, :left}, state) == :ignore)
    assert Page.handle_key({:move, :right}, state) == :ignore
    next = Page.advance(state, 0)
    assert next.match.game.players[1].direction == :east
    assert Page.advance(next, 100).match.game.players[1].direction == :east
  end

  test "pause, settings, restart and exit discard buffered steering" do
    for key <- [{:char, 32}, {:char, ?s}, {:char, ?r}] do
      state = Page.init(countdown_ms: 0, profiles: %{1 => :human})
      assert Page.handle_key({:move, :left}, state) == :ignore
      {:ok, next} = Page.handle_key(key, state)
      next = %{next | screen: :game, paused: false, started: true}
      assert Page.advance(next, 0).match.game.players[1].direction == :north
    end

    state = Page.init(countdown_ms: 0, profiles: %{1 => :human})
    assert Page.handle_key({:move, :left}, state) == :ignore
    assert Page.leave(state) == :ok
    assert Page.advance(state, 0).match.game.players[1].direction == :north
    assert Page.handle_key({:move, :left}, state) == :ignore
    fresh = Page.init(countdown_ms: 0, profiles: %{1 => :human})
    assert Page.advance(fresh, 0).match.game.players[1].direction == :north
  end

  test "steering while paused does not turn after resuming" do
    state = Page.init(countdown_ms: 0, profiles: %{1 => :human})
    {:ok, paused} = Page.handle_key({:char, 32}, state)
    assert Page.handle_key({:move, :left}, paused) == :ignore
    {:ok, next} = Page.handle_key({:char, 32}, paused)
    assert Page.advance(next, 0).match.game.players[1].direction == :north
  end

  test "left and right turns escape every wall on square and wide board presets" do
    for {width, height} <- [{14, 14}, {24, 14}, {23, 23}, {39, 23}, {30, 30}, {51, 30}, {46, 46}, {78, 46}],
        {position, direction, turn, expected, heading} <- [
          {{0, 6}, :west, :left, {0, 7}, :south},
          {{0, 6}, :west, :right, {0, 5}, :north},
          {{width - 1, 6}, :east, :left, {width - 1, 5}, :north},
          {{width - 1, 6}, :east, :right, {width - 1, 7}, :south},
          {{6, 0}, :north, :left, {5, 0}, :west},
          {{6, 0}, :north, :right, {7, 0}, :east},
          {{6, height - 1}, :south, :left, {7, height - 1}, :east},
          {{6, height - 1}, :south, :right, {5, height - 1}, :west}
        ] do
      state = Page.init(countdown_ms: 0, rules: %{width: width, height: height})
      {:ok, board} = Game.new(state.match.game.config, [
        %{id: 1, position: position, direction: direction},
        %{id: 2, position: {div(width, 2), div(height, 2)}, direction: :east}
      ])
      match = Match.new(Game.compact(board), %{1 => :human, 2 => :human})
      refute Match.tick(match).game.players[1].alive
      state = %{state | match: match, due_at: 100}
      assert Page.handle_key({:move, turn}, state) == :ignore
      assert Page.advance(state, 99) == state
      next = Page.advance(state, 100)
      assert next.match.game.tick == 1
      assert next.match.game.players[1].alive
      assert next.match.game.players[1].position == expected
      assert next.match.game.players[1].direction == heading
    end
  end
end
