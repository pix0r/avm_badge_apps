defmodule Badge.App.Beamwars.RenderTest do
  use ExUnit.Case, async: true
  alias Badge.App.Beamwars.{Match, Render}

  test "layout fits the configured board into badge content space" do
    match = Match.demo(%{width: 64, height: 36}, 1)
    layout = Render.layout(match.game.config)
    assert is_struct(layout, Badge.App.Beamwars.Render.Layout)
    assert layout.cell == 4
    assert layout.x >= 0
    assert layout.y >= 25
    assert layout.y + 36 * layout.cell <= 212
    assert Enum.all?(Render.scene(match.game, layout), &is_tuple/1)
  end

  test "classic beam colors and a board that uses the available badge area" do
    assert Enum.map(1..4, &Render.color/1) == [0x0000FF, 0xFF0000, 0x00FF00, 0xFFFF00]
    layout = Render.layout(Match.demo(%{width: 78, height: 46}).game.config)
    assert layout.cell == 4
    assert layout.x == 4
    assert layout.y == 24
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

  test "death effects use the player's color and cannons are present before launch" do
    match = Match.demo(%{width: 78, height: 46})
    layout = Render.layout(match.game.config)
    effects = [%Render.Explosion{id: 2, position: {39, 23}}]
    items = Render.explosions(effects, layout, match.game.arena)
    assert items != []
    assert Enum.all?(items, fn {:rect, _, _, _, _, color} -> color == Render.color(2) end)
    assert Render.cannons(match.game, layout) != []
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
