defmodule Badge.App.Goatwars.PageTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Board, Game, Match, Page}

  test "default pace stays at five steps per second with four or two active players" do
    for profiles <- [%{}, %{3 => :inactive, 4 => :inactive}] do
      state = Page.init(countdown_ms: 0, profiles: profiles) |> Page.advance(0)
      assert Page.advance(state, 199).match.game.tick == 1
      next = Page.advance(state, 200)
      assert next.match.game.tick == 2
      assert Page.advance(next, 399).match.game.tick == 2
      assert Page.advance(next, 400).match.game.tick == 3
      {:ok, restarted} = Page.handle_key({:char, ?r}, next)
      restarted = restarted |> Page.advance(1000) |> Page.advance(4000)
      assert Page.advance(restarted, 4199).match.game.tick == 1
      assert Page.advance(restarted, 4200).match.game.tick == 2
    end
  end

  test "pause and result captions draw without transparent glyph searches" do
    state = Page.init(countdown_ms: 0)
    {:ok, paused} = Page.handle_key({:char, 32}, state)
    result = %{state | match: %{state.match | game: %{state.match.game | status: {:winner, 4}}, awarded_bonus: {4, 3000}}}

    for page <- [paused, result] do
      captions = for {:text, _, y, _, _, background, _} <- Page.render(page), y == 34 or y == 54, do: background
      assert captions == [0x241332, 0x241332]
    end
  end

  test "square middle default fits the screen with a bounded bitmap" do
    state = Page.init(countdown_ms: 0)
    assert {23, 23, bytes} = state.match.game.occupied
    assert byte_size(bytes) == 2116
    assert state.layout.cell == 8
    assert length(Page.render(state)) <= 26
    assert state.match.game.config.step_ms == 200
  end

  test "settings can compare board sizes and rematches retain the selected size" do
    state = Page.init(countdown_ms: 0)

    Enum.reduce([{30, 30, "L", 6, 116}, {46, 46, "XL", 4, 180}, {14, 14, "S", 13, 52}, {23, 23, "M", 8, 88}], state, fn {width, height,
                                                                                                                         label, cell,
                                                                                                                         fence},
                                                                                                                        state ->
      {:ok, settings} = Page.handle_key({:char, ?s}, state)
      {:ok, settings} = Page.handle_key({:char, ?g}, settings)
      assert Page.advance(settings, 5000).match == state.match
      labels = for {:text, _, _, _, _, _, text} <- Page.render(settings), do: text
      assert ("G: Board " <> label <> " " <> Integer.to_string(width) <> "x" <> Integer.to_string(height)) in labels
      {:ok, selected} = Page.handle_key(:enter, settings)
      assert {^width, ^height, _} = selected.match.game.occupied
      assert selected.layout.cell == cell
      assert selected.match.game.arena.next_shrink_tick == fence
      {:ok, rematch} = Page.handle_key({:char, ?r}, selected)
      assert rematch.match.game.config.width == width
      rematch
    end)
  end

  test "square and wide aspects retain size and speed through settings and rematches" do
    for {square, wide, label} <- [{14, 24, "S"}, {23, 39, "M"}, {30, 51, "L"}, {46, 78, "XL"}] do
      state = Page.init(countdown_ms: 0, rules: %{width: square, height: square, step_ms: 130})
      {:ok, settings} = Page.handle_key({:char, ?s}, state)
      labels = for {:text, _, _, _, _, _, text} <- Page.render(settings), do: text
      assert "A: Square" in labels
      assert ("G: Board " <> label <> " " <> Integer.to_string(square) <> "x" <> Integer.to_string(square)) in labels
      {:ok, wide_settings} = Page.handle_key({:char, ?a}, settings)
      {:ok, canceled} = Page.handle_key({:char, ?s}, wide_settings)
      assert canceled.setup.board == {square, square}
      {:ok, game} = Page.handle_key(:enter, wide_settings)
      assert game.setup.board == {wide, square}
      assert game.match.game.config.step_ms == 130
      assert game.match.game.arena.next_shrink_tick == 2 * (wide + square) - 4
      {:ok, rematch} = Page.handle_key({:char, ?r}, game)
      assert rematch.setup.board == {wide, square}
      {:ok, settings} = Page.handle_key({:char, ?s}, rematch)
      assert Enum.any?(Page.render(settings), &match?({:text, _, _, _, _, _, "A: Wide"}, &1))
      {:ok, settings} = Page.handle_key({:char, ?a}, settings)
      {:ok, square_game} = Page.handle_key(:enter, settings)
      assert square_game.setup.board == {square, square}
      assert square_game.match.game.arena.next_shrink_tick == 4 * square - 4
      assert square_game.layout.cell == game.layout.cell
    end
  end

  test "square spawn distances and rendering remain symmetric at all four sizes" do
    for edge <- [14, 23, 30, 46] do
      state = Page.init(countdown_ms: 0, rules: %{width: edge, height: edge})
      players = state.match.game.players
      assert players[1].position == {div(edge, 2), edge - 1}
      assert players[2].position == {div(edge - 1, 2), 0}
      assert players[3].position == {0, div(edge, 2)}
      assert players[4].position == {edge - 1, div(edge - 1, 2)}
      spawns = for {_, player} <- players, do: player.position
      rotated = for {x, y} <- spawns, do: {edge - 1 - y, x}
      assert MapSet.new(rotated) == MapSet.new(spawns)
      assert state.layout.x * 2 + edge * state.layout.cell == 320
      assert state.layout.y >= 24
      assert state.layout.y + edge * state.layout.cell <= 208
    end
  end

  test "settings apply slower steps independently of board size and preserve them on rematch" do
    state = Page.init(countdown_ms: 0)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    {:ok, settings} = Page.handle_key({:char, ?f}, settings)
    assert settings.match.game.config.step_ms == 200
    labels = for {:text, _, _, _, _, _, label} <- Page.render(settings), do: label
    assert "F/V: Step 210ms" in labels
    assert "G: Board M 23x23" in labels
    assert "Z/X" in labels
    assert "1/2" in labels
    assert "9/0" in labels
    {:ok, slow} = Page.handle_key(:enter, settings)
    assert slow.match.game.config.width == 23
    slow = slow |> Page.advance(0) |> Page.advance(3000)
    assert slow.match.game.tick == 1
    assert Page.advance(slow, 3209).match.game.tick == 1
    assert Page.advance(slow, 3210).match.game.tick == 2
    {:ok, rematch} = Page.handle_key({:char, ?r}, slow)
    assert rematch.match.game.config.step_ms == 210
    {:ok, settings} = Page.handle_key({:char, ?s}, rematch)
    {:ok, settings} = Page.handle_key({:char, ?g}, settings)
    {:ok, full} = Page.handle_key(:enter, settings)
    assert full.match.game.config.width == 30
    assert full.match.game.config.step_ms == 210
  end

  test "speed adjusts in ten-millisecond steps with safe upper and lower bounds" do
    {:ok, settings} = Page.handle_key({:char, ?s}, Page.init(loading: false))

    settings =
      Enum.reduce([210, 220, 230], settings, fn expected, settings ->
        {:ok, next} = Page.handle_key({:char, ?f}, settings)
        {:ok, game} = Page.handle_key(:enter, next)
        assert game.match.game.config.step_ms == expected
        next
      end)

    {:ok, settings} = Page.handle_key({:char, ?v}, settings)
    {:ok, game} = Page.handle_key(:enter, settings)
    assert game.match.game.config.step_ms == 220

    for {key, expected} <- [{?v, 50}, {?f, 400}] do
      limit =
        Enum.reduce(1..50, settings, fn _, current ->
          {:ok, next} = Page.handle_key({:char, key}, current)
          next
        end)

      {:ok, game} = Page.handle_key(:enter, limit)
      assert game.match.game.config.step_ms == expected
    end
  end

  test "fast gameplay asks for its cadence while menus keep their normal cadence" do
    state = Page.init(countdown_ms: 0, rules: %{width: 51, height: 30, step_ms: 50})
    assert Page.tick_interval(state) == 50
    assert Page.refresh(state) == 50
    next = Page.advance(state, 0)
    assert Page.advance(next, 49).match.game.tick == 1
    assert Page.advance(next, 50).match.game.tick == 2
    {:ok, paused} = Page.handle_key({:char, 32}, state)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)

    for page <- [paused, settings, Page.init(loading: false)] do
      assert Page.tick_interval(page) == 100
      assert Page.refresh(page) == 100
    end
  end

  test "small callback jitter does not halve a finely selected game speed" do
    state = Page.init(countdown_ms: 0, rules: %{width: 51, height: 30, step_ms: 110})
    state = Page.advance(state, 0)
    assert Page.advance(state, 109).match.game.tick == 1
    state = Enum.reduce([220, 329, 440, 549], state, &Page.advance(&2, &1))
    assert state.match.game.tick == 5
    assert state.due_at == 550
    late = Page.advance(state, 10_000)
    assert late.match.game.tick == 6
    assert late.due_at == 10_110
  end

  test "canceling a speed change retains a custom pace" do
    state = Page.init(loading: false, rules: %{width: 40, height: 30, step_ms: 250})
    {:ok, state} = Page.handle_key(:enter, state)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    {:ok, settings} = Page.handle_key({:char, ?f}, settings)
    {:ok, canceled} = Page.handle_key({:char, ?s}, settings)
    {:ok, rematch} = Page.handle_key({:char, ?r}, canceled)
    assert rematch.match.game.config.step_ms == 250
  end

  test "canceling a board-size change preserves custom rules" do
    state = Page.init(loading: false, rules: %{width: 40, height: 30, shrink_after: 99, step_ms: 200})
    {:ok, state} = Page.handle_key(:enter, state)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    {:ok, settings} = Page.handle_key({:char, ?g}, settings)
    {:ok, canceled} = Page.handle_key({:char, ?s}, settings)
    {:ok, rematch} = Page.handle_key({:char, ?r}, canceled)
    assert rematch.match.game.config.width == 40
    assert rematch.match.game.config.height == 30
    assert rematch.match.game.config.shrink_after == 99
    assert rematch.match.game.config.step_ms == 200
  end

  test "score text covers its background without transparent glyph searches" do
    items = Page.render(Page.init(countdown_ms: 0))
    footer = for {:text, _, y, _, _, background, _} <- items, y >= 210, do: background
    assert length(footer) == 12
    assert Enum.all?(footer, &(&1 == 0x241332))
    assert {:rect, 0, 209, 320, 31, 0x241332} in items
  end

  test "simultaneous knockouts show brief goat calls without adding board drawing commands" do
    state = Page.init(countdown_ms: 0, rules: %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8})

    {:ok, game} =
      Game.new(state.match.game.config, [
        %{id: 1, position: {20, 35}, direction: :north},
        %{id: 2, position: {38, 20}, direction: :east},
        %{id: 3, position: {40, 20}, direction: :west},
        %{id: 4, position: {60, 20}, direction: :west}
      ])

    game = %{game | occupied: Board.new(game.config, game.occupied), tick: 30}
    scores = %{1 => 750, 2 => 750, 3 => 750, 4 => 750}
    match = Match.new(game, %{1 => :human, 2 => :human, 3 => :human, 4 => :human}, record_replay: false)
    state = %{state | match: %{match | scores: scores, totals: scores}, scores: scores}
    state = Page.advance(state, 3000)

    assert Enum.count(state.match.events, &match?({:crashed, _, _}, &1)) == 2
    items = Page.render(state)
    assert length(items) <= 26
    assert {:text, 47, 210, :default16px, 0xFFFFFF, 0x241332, "BAA!"} in items
    assert {:text, 90, 210, :default16px, 0xFFFFFF, 0x241332, "BAA!"} in items
    assert {:text, 4, 210, :default16px, 0xFFFFFF, 0x241332, "775"} in items
    assert state.match.scores[2] == 750
    expired = Enum.reduce(31..36, state, &Page.advance(&2, &1 * 100))
    refute Enum.any?(Page.render(expired), &match?({:text, _, _, _, _, _, "BAA!"}, &1))
    assert {:text, 47, 210, :default16px, 0xFFFFFF, 0x241332, "750"} in Page.render(expired)
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
    assert Page.handle_key({:move, :left}, state) == :ignore
    {:ok, bots} = Page.handle_key({:char, ?b}, state)
    assert_simple(bots)
    assert_simple(Page.advance(bots, 0))
  end

  defp assert_simple(state) do
    for {_, {module, _memory}} <- state.match.controllers,
        do: assert(module == Badge.App.Goatwars.SimpleBot)
  end

  test "badge play retains no replay history across ticks and rematches" do
    state = Page.init(countdown_ms: 0)
    state = Enum.reduce(0..30, state, fn tick, state -> Page.advance(state, tick * 200) end)
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
    state = Enum.reduce(0..9, state, fn tick, state -> Page.advance(state, tick * 200) end)
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
    assert state.match.game.config.width == 23
    assert state.match.game.config.height == 23
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
    state = Page.init(loading: false)
    {:ok, state} = Page.handle_key(:enter, state)
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
    assert Page.advance(next, 1200).match.game.tick == 2
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
    for key <- [{:move, :left}, {:char, ?z}, {:char, ?1}, {:char, ?9}],
      do: assert(Page.handle_key(key, state) == :ignore)
    state = Page.advance(state, 1000)
    assert state.match.controllers == %{1 => :human, 2 => :human, 3 => :human, 4 => :human}
    assert state.match.pending == %{}
    assert Enum.map(1..4, &state.match.game.players[&1].direction) == [:west, :east, :north, :south]
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
    full = Page.init(countdown_ms: 0, rules: %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8})
    {:ok, full} = Page.handle_key({:char, ?t}, full)
    state = %{full | match: %{full.match | game: %{full.match.game | tick: 97}}}
    log = ExUnit.CaptureIO.capture_io(fn -> Page.render(state) end)
    assert log =~ "GW_DEVICE mode=bitmap tick=97 phase=render"
    {:ok, quiet} = Page.handle_key({:char, ?t}, state)
    assert ExUnit.CaptureIO.capture_io(fn -> Page.render(quiet) end) == ""
  end

  test "footer text and player stripes clear the bottom arena wall" do
    state = Page.init(countdown_ms: 0)
    wall_y = state.layout.y + state.match.game.config.height * state.layout.cell
    items = Page.render(state)
    assert {:text, 180, 210, :default16px, 0xFFFFFF, 0x241332, "Energy"} in items

    for {:rect, x, y, 36, _height, _color} <- items, x in [4, 47, 90, 133] do
      assert y > wall_y
    end
  end
end
