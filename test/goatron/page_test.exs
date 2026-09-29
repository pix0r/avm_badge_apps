defmodule Badge.App.Goatron.PageTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatron.{Match, Page, Render}

  test "the badge page owns typed demo state and produces content" do
    state = Page.init()
    assert is_struct(state, Badge.App.Goatron.Page.State)
    assert is_struct(state.match, Match)
    assert is_struct(state.layout, Render.Layout)
    assert Enum.all?(Page.render(state), &is_tuple/1)
  end

  test "timing respects configured speed and pause freezes the match" do
    state = Page.init()
    next = Page.advance(state, 1000)
    assert next.match.game.tick == 1
    assert Page.advance(next, 1050).match.game.tick == 1
    assert Page.advance(next, 1100).match.game.tick == 2
    {:ok, paused} = Page.handle_key({:char, 32}, next)
    assert Page.advance(paused, 5000).match == paused.match
  end

  test "the first frame advances when monotonic time is negative" do
    state = Page.init()
    next = Page.advance(state, -576_000_000)
    assert next.match.game.tick == 1
    assert Page.advance(next, -575_999_950).match.game.tick == 1
  end

  test "four key pairs can take over four bots and apply one turn" do
    state = Page.init()

    state =
      Enum.reduce([{:move, :left}, {:char, ?a}, {:char, ?j}, {:char, ?v}], state, fn key, state ->
        {:ok, state} = Page.handle_key(key, state)
        state
      end)

    assert state.match.controllers == %{1 => :human, 2 => :human, 3 => :human, 4 => :human}
    assert state.match.pending == %{1 => :left, 2 => :left, 3 => :left, 4 => :left}
    assert Page.advance(state, 1000).match.pending == %{}
  end

  test "rounds restart after a visible result pause and scores persist" do
    state = Page.init()
    match = Match.run(state.match, 64 * 36)
    state = %{state | match: match}
    state = Page.advance(state, 1000)
    assert state.result_until == 3000
    assert Page.advance(state, 2900).round == 1
    restarted = Page.advance(state, 3000)
    assert restarted.round == 2
    assert restarted.match.game.tick == 0
    assert restarted.wins == state.wins
  end
end
