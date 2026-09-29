defmodule Badge.App.Goatron.Render.Layout do
  @moduledoc "Pixel geometry for a badge-sized arena."
  @enforce_keys [:x, :y, :cell]
  defstruct [:x, :y, :cell]
end

defmodule Badge.App.Goatron.Render do
  @moduledoc "AtomGL content items, drawn front-to-back, for a 320×240 badge."
  alias Badge.App.Goatron.{Arena, Config, Game, State}
  alias __MODULE__.Layout

  @board 0x09131C
  @grid 0x142330
  @wall 0x477083
  @danger 0xFF694D

  def color(1), do: 0x39DDF1
  def color(2), do: 0xFFCA62
  def color(3), do: 0xF878A7
  def color(4), do: 0x88E3A3
  def color(_), do: 0xA4B4FF

  def layout(%Config{width: width, height: height}) do
    cell = max(1, min(div(304, width), div(164, height)))
    %Layout{x: div(320 - width * cell, 2), y: 44 + div(164 - height * cell, 2), cell: cell}
  end

  @doc "Heads and trails over a grid; warning marks cover the ring about to disappear."
  def scene(%State{} = game, %Layout{} = layout, phase \\ nil) do
    phase = phase || game.tick

    heads(game, layout) ++
      warning_ring(game, layout, phase) ++
      trails(game, layout) ++
      frame(game.arena, layout) ++ grid(game.arena, layout) ++ [background(game.arena, layout)]
  end

  def warning_color(game, phase) do
    if Arena.warning?(game.arena, game.config, game.tick) and rem(div(phase, 2), 2) == 0, do: @danger, else: @wall
  end

  defp heads(game, layout) do
    for player <- Game.living(game), Arena.contains?(game.arena, player.position) do
      {x, y} = point(player.position, layout)
      {:rect, x, y, layout.cell, layout.cell, 0xFFFFFF}
    end
  end

  defp trails(game, layout) do
    runs =
      game.occupied
      |> Enum.filter(fn {position, _id} -> Arena.contains?(game.arena, position) end)
      |> Enum.map(fn {{x, y}, id} -> {y, x, id} end)
      |> :lists.sort()
      |> Enum.reduce([], &join_run/2)

    for {row, column, id, count} <- runs do
      {x, y} = point({column, row}, layout)
      {:rect, x, y, count * layout.cell, layout.cell, color(id)}
    end
  end

  defp join_run({row, column, id}, [{row, start, id, count} | rest]) when column == start + count,
    do: [{row, start, id, count + 1} | rest]

  defp join_run({row, column, id}, runs), do: [{row, column, id, 1} | runs]

  defp warning_ring(game, layout, phase) do
    if Arena.warning?(game.arena, game.config, game.tick) do
      arena = game.arena

      cells =
        for x <- arena.left..arena.right, y <- [arena.top, arena.bottom], rem(x, 2) == 0, do: {x, y}

      sides =
        for y <- arena.top..arena.bottom, x <- [arena.left, arena.right], rem(y, 2) == 0, do: {x, y}

      for cell <- cells ++ sides do
        {x, y} = point(cell, layout)
        {:rect, x, y, layout.cell, layout.cell, warning_color(game, phase)}
      end
    else
      []
    end
  end

  defp frame(arena, layout) do
    {x, y} = point({arena.left, arena.top}, layout)
    w = (arena.right - arena.left + 1) * layout.cell
    h = (arena.bottom - arena.top + 1) * layout.cell

    [
      {:rect, x - 1, y - 1, w + 2, 1, @wall},
      {:rect, x - 1, y + h, w + 2, 1, @wall},
      {:rect, x - 1, y, 1, h, @wall},
      {:rect, x + w, y, 1, h, @wall}
    ]
  end

  defp grid(arena, layout) do
    {left, top} = point({arena.left, arena.top}, layout)
    w = (arena.right - arena.left + 1) * layout.cell
    h = (arena.bottom - arena.top + 1) * layout.cell
    vertical = for x <- arena.left..arena.right, rem(x, 8) == 0, do: {:rect, layout.x + x * layout.cell, top, 1, h, @grid}
    horizontal = for y <- arena.top..arena.bottom, rem(y, 8) == 0, do: {:rect, left, layout.y + y * layout.cell, w, 1, @grid}
    vertical ++ horizontal
  end

  defp background(arena, layout) do
    {x, y} = point({arena.left, arena.top}, layout)
    {:rect, x, y, (arena.right - arena.left + 1) * layout.cell, (arena.bottom - arena.top + 1) * layout.cell, @board}
  end

  defp point({x, y}, layout), do: {layout.x + x * layout.cell, layout.y + y * layout.cell}
end
