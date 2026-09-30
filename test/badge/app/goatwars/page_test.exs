defmodule Badge.App.Goatwars.PageTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Match, Page}

  test "the badge page owns plain-map demo state and produces content" do
    state = Page.init(countdown_ms: 0)
    refute is_struct(state)
    refute is_struct(state.match)
    refute is_struct(state.layout)
    assert Enum.all?(Page.render(state), &is_tuple/1)
  end

  test "badge ticks and rematches do not retain unused replay history" do
    state = Page.init(countdown_ms: 0)
    state = Enum.reduce(0..9, state, fn tick, state -> Page.advance(state, tick * 100) end)
    assert state.match.game.tick == 10
    assert state.match.replay == []

    {:ok, state} = Page.handle_key({:char, ?r}, state)
    state = state |> Page.advance(2000) |> Page.advance(5000)
    assert state.match.game.tick == 1
    assert state.match.replay == []
  end

  test "GoatWars shows bottom scores and board energy without a round or shrink label" do
    state = Page.init(countdown_ms: 0)
    assert Page.title() == "GoatWars"
    assert state.match.game.config.width == 78
    assert state.match.game.config.height == 46
    labels = for {:text, _, _, _, _, _, label} <- Page.render(state), do: label
    assert "Energy" in labels
    refute Enum.any?(labels, &(String.contains?(&1, "ROUND") or String.contains?(&1, "SHRINK")))
    next = Page.advance(state, 1000)
    assert next.scores == %{1 => 25, 2 => 25, 3 => 25, 4 => 25}
  end

  test "demo rules and per-rider AI parameters are configurable and survive rematches" do
    state =
      Page.init(
        countdown_ms: 0,
        rules: %{width: 40, height: 30, step_ms: 200, retract_speed: 3},
        profiles: %{1 => :beginner}
      )

    assert state.match.game.config.step_ms == 200
    {_, pilot} = state.match.controllers[1]
    assert pilot.profile.reaction_ticks == 5
    {:ok, restarted} = Page.handle_key({:char, ?r}, state)
    {_, next_pilot} = restarted.match.controllers[1]
    assert next_pilot.profile == pilot.profile
    assert restarted.match.game.config.retract_speed == 3
  end

  test "launch counts down without movement or scoring, then starts" do
    state = Page.init()
    state = Page.advance(state, 1000)
    assert state.match.game.tick == 0
    assert state.scores == %{}
    labels = for {:text, _, _, _, _, _, label} <- Page.render(state), do: label
    assert "3" in labels
    state = Page.advance(state, 2000)
    assert state.launch_remaining == 2000
    state = Page.advance(state, 4000)
    assert state.started
    assert state.match.game.tick == 1
  end

  test "settings suspend play, configure inactive slots and start a fresh countdown" do
    state = Page.init(countdown_ms: 0)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    assert settings.screen == :settings
    assert Page.advance(settings, 5000).match == state.match
    settings = %{settings | draft: Badge.App.Goatwars.Setup.mode(settings.draft, 4, :inactive)}
    {:ok, started} = Page.handle_key({:edit, :newline}, settings)
    assert started.screen == :game
    refute Map.has_key?(started.match.game.players, 4)
    assert started.launch_remaining == 3000
  end

  test "applying a changed AI level does not retain the old pilot profile" do
    state = Page.init(countdown_ms: 0)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    {:ok, settings} = Page.handle_key({:move, :right}, settings)
    {:ok, game} = Page.handle_key({:edit, :newline}, settings)
    {_, pilot} = game.match.controllers[1]
    assert pilot.profile == Badge.App.Goatwars.Bot.Profile.new(:expert)
  end

  test "timing respects configured speed and pause freezes the match" do
    state = Page.init(countdown_ms: 0)
    next = Page.advance(state, 1000)
    assert next.match.game.tick == 1
    assert Page.advance(next, 1050).match.game.tick == 1
    assert Page.advance(next, 1100).match.game.tick == 2
    {:ok, paused} = Page.handle_key({:char, 32}, next)
    assert Page.advance(paused, 5000).match == paused.match
  end

  test "the first frame advances when monotonic time is negative" do
    state = Page.init(countdown_ms: 0)
    next = Page.advance(state, -576_000_000)
    assert next.match.game.tick == 1
    assert Page.advance(next, -575_999_950).match.game.tick == 1
  end

  test "four key pairs can take over four bots and apply one turn" do
    state = Page.init(countdown_ms: 0)

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
    state = Page.init(countdown_ms: 0)
    match = Match.run(state.match, 64 * 36)
    state = %{state | match: match}
    state = Page.advance(state, 1000)
    assert state.result_until == 3000
    assert Page.advance(state, 2900).round == 1
    restarted = Page.advance(state, 3000)
    assert restarted.round == 2
    assert restarted.match.game.tick == 0
    assert restarted.scores == state.scores
  end

  test "footer text and player stripes clear the bottom arena wall" do
    state = Page.init()
    wall_y = state.layout.y + state.match.game.config.height * state.layout.cell
    items = Page.render(state)
    assert {:text, 180, 210, :default16px, 0xFFFFFF, :transparent, "Energy"} in items

    for {:rect, x, y, 36, _height, _color} <- items, x in [4, 47, 90, 133] do
      assert y > wall_y
    end
  end
end
