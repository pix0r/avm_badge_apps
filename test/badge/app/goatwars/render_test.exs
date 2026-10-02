defmodule Badge.App.Goatwars.RenderTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Board, Game, Match, Render}

  test "contraction warning has a bounded drawing budget on a full size board" do
    game = Game.compact(Match.demo(%{width: 78, height: 46, shrink_after: 12, warning_ticks: 4}).game)
    game = %{game | tick: 8}
    layout = Render.layout(game.config)
    warning = Render.scene(game, layout, 0)
    quiet = Render.scene(%{game | tick: 0}, layout, 0)
    assert length(warning) <= length(quiet) + 4
    assert Enum.any?(warning, &match?({:rect, _, _, _, _, 0xFF694D}, &1))
    refute Enum.any?(Render.scene(game, layout, 2), &match?({:rect, _, _, _, _, 0xFF694D}, &1))
  end

  test "layout fits the configured board into badge content space" do
    match = Match.demo(%{width: 64, height: 36}, 1)
    layout = Render.layout(match.game.config)
    refute is_struct(layout)
    assert layout.cell == 4
    assert layout.x >= 0
    assert layout.y >= 25
    assert layout.y + 36 * layout.cell <= 212
    assert Enum.all?(Render.scene(match.game, layout), &is_tuple/1)
  end

  test "complementary trail colors and a board that uses the available badge area" do
    assert Enum.map(1..4, &Render.color/1) == [0xC840FF, 0x00FF88, 0xFF285C, 0x7040FF]
    layout = Render.layout(Match.demo(%{width: 78, height: 46}).game.config)
    assert layout.cell == 4
    assert layout.x == 4
    assert layout.y == 24
  end

  test "map and bitmap rendering use the same trail colors and purple board" do
    occupied = %{{1, 1} => 1, {2, 1} => 2, {3, 1} => 3, {4, 1} => 4}
    game = %{Match.demo(%{width: 16, height: 12}).game | players: %{}, occupied: occupied}
    layout = Render.layout(game.config)
    items = Render.scene(game, layout)

    assert List.last(items) == {:rect, layout.x, layout.y, 16 * layout.cell, 12 * layout.cell, 0x3D175A}
    assert Render.warning_color(game, 0) == 0x9B85AD

    bitmap = Board.new(game.config, occupied)
    bitmap_items = Render.scene(%{game | occupied: bitmap}, layout)

    assert {:scaled_cropped_image, layout.x, layout.y, 16 * layout.cell, 12 * layout.cell, :transparent, 0, 0, layout.cell, layout.cell, [],
            {:rgba8888, 16, 12, elem(bitmap, 2)}} in bitmap_items

    for {position = {column, row}, id} <- occupied do
      color = Render.color(id)
      assert {:rect, layout.x + column * layout.cell, layout.y + row * layout.cell, layout.cell, layout.cell, color} in items
      assert :binary.part(elem(bitmap, 2), (row * 16 + column) * 4, 4) == <<color::24, 255>>
      assert Board.get(bitmap, position) == id
    end

    assert :binary.part(elem(bitmap, 2), 0, 4) == <<61, 23, 90, 255>>
  end

  test "empty boards have a uniform background and only four fence commands" do
    for {width, height} <- [{14, 14}, {23, 23}, {30, 30}, {46, 46}, {24, 14}, {39, 23}, {51, 30}, {78, 46}], inset <- [0, 1, 5] do
      game = Match.demo(%{width: width, height: height}).game

      game = %{
        game
        | players: %{},
          occupied: %{},
          arena: %{game.arena | left: inset, top: inset, right: width - inset - 1, bottom: height - inset - 1}
      }

      layout = Render.layout(game.config)

      for board <- [game, Game.compact(game)] do
        assert length(Render.scene(board, layout)) == 5
      end
    end
  end

  test "the warning ring visibly flashes before contraction" do
    match = Match.demo(%{width: 32, height: 24, shrink_after: 12, warning_ticks: 4}, 1)
    game = %{match.game | tick: 8}
    layout = Render.layout(game.config)
    assert Render.warning_color(game, 0) != Render.warning_color(game, 2)
    refute Render.scene(game, layout, 0) == Render.scene(game, layout, 2)
    quiet = %{game | tick: 0}
    assert Render.warning_color(quiet, 0) == Render.warning_color(quiet, 2)
  end

  test "trails on a removed ring are hidden, without mutating the game" do
    match = Match.demo(%{width: 32, height: 24}, 1)
    game = match.game

    game = %{
      game
      | occupied: Map.put(game.occupied, {0, 0}, 1),
        arena: %{game.arena | left: 1, top: 1, right: 30, bottom: 22, inset: 1}
    }

    layout = Render.layout(game.config)
    rect = {:rect, layout.x, layout.y, layout.cell, layout.cell, Render.color(1)}
    refute rect in Render.scene(game, layout)
    assert game.occupied[{0, 0}] == 1
  end

  test "cannons expose colored emitters at all four launch edges" do
    match = Match.demo(%{width: 78, height: 46})
    layout = Render.layout(match.game.config)
    items = Render.cannons(match.game, layout)

    for {id, player} <- match.game.players do
      {column, row} = player.position
      x = layout.x + column * layout.cell
      y = layout.y + row * layout.cell

      visible =
        Enum.find(items, fn {:rect, left, top, width, height, _color} ->
          x >= left and x < left + width and y >= top and y < top + height
        end)

      assert elem(visible, 5) == Render.color(id)
    end
  end
end
