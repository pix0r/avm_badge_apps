defmodule Badge.App.Goatwars.TitleTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Page, Render}

  test "opening the page waits on the title until Enter starts the countdown" do
    title = Page.init(loading: false)
    assert title.screen == :title
    assert Page.advance(title, 10_000) == title
    assert title.match.game.tick == 0
    assert Page.handle_key({:move, :left}, title) == :ignore
    assert Page.handle_key({:char, ?r}, title) == :ignore

    {:ok, countdown} = Page.handle_key(:enter, title)
    assert countdown.screen == :game
    refute countdown.started
    assert countdown.launch_remaining == 3000
    assert countdown.scores == %{}
    countdown = Page.advance(countdown, -10_000)
    assert countdown.match.game.tick == 0
    started = Page.advance(countdown, -7_000)
    assert started.started
    assert started.match.game.tick == 1
  end

  test "all Enter encodings start play from the title" do
    for key <- [:enter, {:edit, :newline}, {:char, 13}] do
      assert {:ok, %{screen: :game, started: false}} = Page.handle_key(key, Page.init(loading: false))
    end
  end

  test "canceling title settings returns to the title and applying settings starts play" do
    title = Page.init(loading: false)
    {:ok, settings} = Page.handle_key({:char, ?s}, title)
    assert settings.screen == :settings
    assert Page.advance(settings, 1000) == settings
    {:ok, changed} = Page.handle_key({:char, ?g}, settings)
    {:ok, canceled} = Page.handle_key({:char, ?s}, changed)
    assert canceled.screen == :title
    assert canceled.setup == title.setup
    assert Page.advance(canceled, 5000).match.game.tick == 0
    {:ok, game} = Page.handle_key(:enter, changed)
    assert game.screen == :game
    assert {game.match.game.config.width, game.match.game.config.height} == {78, 46}
    assert game.launch_remaining == 3000
  end

  test "title pause winner and draw reuse cached goat artwork" do
    title = Page.init(loading: false)
    {:ok, countdown} = Page.handle_key(:enter, title)
    game = countdown |> Page.advance(0) |> Page.advance(3000)
    {:ok, paused} = Page.handle_key({:char, 32}, game)
    winner = %{game | match: %{game.match | game: %{game.match.game | status: {:winner, 2}}, awarded_bonus: {2, 120}}}
    draw = %{game | match: %{game.match | game: %{game.match.game | status: :draw}, awarded_bonus: nil}}

    for screen <- [title, paused, winner, draw] do
      items = Page.render(screen)
      goats = for {:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, {:rgba8888, 96, 64, bytes}} <- items, do: bytes
      assert [bytes] = goats
      assert byte_size(bytes) == 24_576
      assert :erts_debug.same(bytes, elem(title.art.goat, 3))
      assert length(items) < 60
      assert Enum.all?(items, &within_content?/1)
    end

    labels = fn state -> for {:text, _, _, _, _, _, label} <- Page.render(state), do: label end
    assert "Enter: play" in labels.(title)
    assert "DON'T LET" in labels.(title)
    assert "IT CRASH" in labels.(title)
    assert "PAUSED" in labels.(paused)
    assert "PLAYER 2 WINS" in labels.(winner)
    assert "BONUS 120" in labels.(winner)
    assert "DRAW" in labels.(draw)
    assert length(Page.render(game)) <= 26
    refute Enum.any?(Page.render(game), &match?({:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, {:rgba8888, 96, 64, _}}, &1))
  end

  test "a separate board countdown shows four cannons without moving riders" do
    for {width, height} <- [{24, 14}, {51, 30}, {78, 46}] do
      title = Page.init(loading: false, rules: %{width: width, height: height})
      {:ok, countdown} = Page.handle_key(:enter, title)
      countdown = Page.advance(countdown, 0)

      for {now, digit} <- [{0, "3"}, {1000, "2"}, {2000, "1"}] do
        state = Page.advance(countdown, now)
        assert state.match.game.tick == 0
        assert state.scores == %{}
        assert state.match.game.players == title.match.game.players
        items = Page.render(state)
        assert Enum.any?(items, &match?({:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, {:rgba8888, ^width, ^height, _}}, &1))
        refute Enum.any?(items, &match?({:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, {:rgba8888, 96, 64, _}}, &1))
        assert Enum.any?(items, &match?({:text, _, _, _, _, _, ^digit}, &1))
        refute Enum.any?(items, &match?({:text, _, _, _, _, _, "DON'T LET IT CRASH"}, &1))

        for {id, player} <- state.match.game.players do
          {column, row} = player.position
          %{x: x, y: y, cell: cell} = state.layout
          assert {:rect, x + column * cell, y + row * cell, cell, cell, Render.color(id)} in items
        end

        assert length(items) < 60
      end

      assert Page.advance(countdown, 3000).started
    end
  end

  test "purple scenery and dark player labels keep the theme readable" do
    title = Page.init(loading: false)
    assert {:rect, 0, 24, 320, 216, 0x241332} in Page.render(title)
    assert Enum.any?(Page.render(title), &match?({:scaled_cropped_image, 16, 28, 288, 80, _, _, _, _, _, _, {:rgba8888, 144, 40, _}}, &1))
    {:ok, settings} = Page.handle_key({:char, ?s}, title)
    assert {:text, 8, 53, :default16px, 0x241332, :transparent, ">P1"} in Page.render(settings)
  end

  test "skipping the launch countdown still permits goat themed pause and rematch" do
    game = Page.init(countdown_ms: 0)
    assert game.screen == :game
    assert game.started
    {:ok, paused} = Page.handle_key({:char, 32}, game)
    assert Enum.any?(Page.render(paused), &match?({:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, {:rgba8888, 96, 64, _}}, &1))
    {:ok, restarted} = Page.handle_key({:char, ?r}, game)
    assert restarted.screen == :game
    refute restarted.started
    assert restarted.launch_remaining == 3000
  end

  defp within_content?({:rect, x, y, w, h, _}), do: x >= 0 and y >= 24 and x + w <= 320 and y + h <= 240
  defp within_content?({:text, x, y, :default16px, _, _, text}), do: x >= 0 and y >= 24 and x + byte_size(text) * 8 <= 320 and y + 16 <= 240
  defp within_content?({:scaled_cropped_image, x, y, w, h, _, _, _, _, _, _, _}), do: x >= 0 and y >= 24 and x + w <= 320 and y + h <= 240
end
