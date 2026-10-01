defmodule Badge.App.Goatwars.PageTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Match, Page}

  test "simultaneous knockouts show brief goat calls without adding board drawing commands" do
    state = Enum.reduce(0..30, Page.init(countdown_ms: 0), &Page.advance(&2, &1 * 100))
    assert Enum.count(state.match.events, &match?({:crashed, _, _}, &1)) == 2
    items = Page.render(state)
    assert length(items) <= 25
    assert {:text, 47, 210, :default16px, 0xFFFFFF, :transparent, "BAA!"} in items
    assert {:text, 90, 210, :default16px, 0xFFFFFF, :transparent, "BAA!"} in items
    assert {:text, 4, 210, :default16px, 0xFFFFFF, :transparent, "775"} in items
    assert state.match.scores[2] == 750
    expired = Enum.reduce(31..36, state, &Page.advance(&2, &1 * 100))
    refute Enum.any?(Page.render(expired), &match?({:text, _, _, _, _, _, "BAA!"}, &1))
    assert {:text, 47, 210, :default16px, 0xFFFFFF, :transparent, "750"} in Page.render(expired)
  end

  test "badge opponents stay simple across rematches, settings and the B shortcut" do
    state = Page.init(countdown_ms: 0)
    assert_simple(state)
    {:ok, restarted} = Page.handle_key({:char, ?r}, state)
    assert_simple(restarted)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    {:ok, settings} = Page.handle_key({:move, :right}, settings)
    {:ok, applied} = Page.handle_key(:enter, settings)
    assert_simple(applied)
    {:ok, human} = Page.handle_key({:move, :left}, state)
    {:ok, bots} = Page.handle_key({:char, ?b}, human)
    assert_simple(bots)
  end

  defp assert_simple(state) do
    for {_, {module, _memory}} <- state.match.controllers,
        do: assert(module == Badge.App.Goatwars.SimpleBot)
  end

  test "badge play retains no replay history across ticks and rematches" do
    state = Page.init(countdown_ms: 0)
    state = Enum.reduce(0..30, state, fn tick, state -> Page.advance(state, tick * 100) end)
    assert state.match.replay == []
    {:ok, state} = Page.handle_key({:char, ?r}, state)
    state = state |> Page.advance(4000) |> Page.advance(7000)
    assert state.match.replay == []
  end

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

  test "badge settings offer only human, simple AI and inactive" do
    state = Page.init(countdown_ms: 0, profiles: %{1 => :human})
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    {:ok, settings} = Page.handle_key({:move, :right}, settings)
    assert settings.draft.slots[1].mode == :intermediate
    labels = for {:text, _, _, _, _, _, label} <- Page.render(settings), do: label
    assert "AI Simple" in labels
    {:ok, game} = Page.handle_key(:enter, settings)
    assert_simple(game)
    {:ok, settings} = Page.handle_key({:char, ?s}, game)
    {:ok, settings} = Page.handle_key({:move, :right}, settings)
    assert settings.draft.slots[1].mode == :inactive
    {:ok, settings} = Page.handle_key({:move, :right}, settings)
    assert settings.draft.slots[1].mode == :human
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

  test "timing diagnostics can compare bitmap and legacy storage on the badge" do
    state = Page.init(countdown_ms: 0)
    assert Page.handle_key({:char, ?m}, state) == :ignore
    {:ok, measured} = Page.handle_key({:char, ?t}, state)
    assert measured.benchmark
    measured = Enum.reduce(0..19, measured, &Page.advance(&2, &1 * 100))
    {:ok, legacy} = Page.handle_key({:char, ?m}, measured)
    assert is_map(legacy.match.game.occupied)
    assert legacy.scores == %{}
    {:ok, bitmap} = Page.handle_key({:char, ?m}, legacy)
    assert is_tuple(bitmap.match.game.occupied)
    assert legacy.match.controllers == bitmap.match.controllers
    assert bitmap.match.game.tick == 0
    state = Enum.reduce(0..96, measured, &Page.advance(&2, &1 * 100))
    log = ExUnit.CaptureIO.capture_io(fn -> Page.render(state) end)
    assert log =~ "GW_DEVICE mode=bitmap tick=97 phase=render"
    {:ok, quiet} = Page.handle_key({:char, ?t}, state)
    assert ExUnit.CaptureIO.capture_io(fn -> Page.render(quiet) end) == ""
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
