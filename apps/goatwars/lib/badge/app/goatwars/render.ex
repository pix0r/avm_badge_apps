defmodule Badge.App.Goatwars.Render do
  @moduledoc "AtomGL content items, drawn front-to-back, for a 320×240 badge."
  alias Badge.App.Goatwars.{Arena, Game}
  alias __MODULE__.Layout

  @board 0x3D175A
  @wall 0x9B85AD
  @danger 0xFF694D

  def color(1), do: 0xC840FF
  def color(2), do: 0x00FF88
  def color(3), do: 0xFF285C
  def color(4), do: 0x7040FF
  def color(_), do: 0xA4B4FF

  def layout(%{width: width, height: height}) do
    cell = max(1, min(div(312, width), div(184, height)))
    Layout.new(div(320 - width * cell, 2), 24 + div(184 - height * cell, 2), cell)
  end

  @doc "Heads and trails; the fence flashes before contraction."
  def scene(game, layout, phase \\ nil)

  def scene(%{occupied: {_, _, _}} = game, layout, phase) do
    heads(game, layout) ++
      trails(game, layout) ++ frame(Map.fetch!(game, :arena), layout, warning_color(game, phase || Map.fetch!(game, :tick)))
  end

  def scene(%{occupied: _} = game, %{cell: _} = layout, phase) do
    phase = phase || Map.fetch!(game, :tick)

    heads(game, layout) ++
      trails(game, layout) ++
      frame(Map.fetch!(game, :arena), layout, warning_color(game, phase)) ++
      [background(Map.fetch!(game, :arena), layout)]
  end

  def cannons(game, layout) do
    Enum.flat_map(Game.living(game), fn player ->
      {x, y} = point(Map.fetch!(player, :position), layout)
      c = Map.fetch!(layout, :cell)
      left = min(max(x - c, Map.fetch!(layout, :x)), Map.fetch!(layout, :x) + Map.fetch!(Map.fetch!(game, :config), :width) * c - 3 * c)
      top = min(max(y - c, Map.fetch!(layout, :y)), Map.fetch!(layout, :y) + Map.fetch!(Map.fetch!(game, :config), :height) * c - 3 * c)

      [
        {:rect, x, y, c, c, color(Map.fetch!(player, :id))},
        {:rect, left + c, top + c, c, c, color(Map.fetch!(player, :id))},
        {:rect, left + 1, top + 1, max(c * 3 - 2, 1), max(c * 3 - 2, 1), @wall}
      ]
    end)
  end

  def warning_color(game, phase) do
    if Arena.warning?(Map.fetch!(game, :arena), Map.fetch!(game, :config), Map.fetch!(game, :tick)) and rem(div(phase, 2), 2) == 0,
      do: @danger,
      else: @wall
  end

  defp heads(%{arena: arena} = game, layout), do: heads(Game.living(game), arena, layout)
  defp heads([], _arena, _layout), do: []

  defp heads([%{position: position} | rest], arena, %{cell: cell} = layout) do
    if Arena.contains?(arena, position) do
      {x, y} = point(position, layout)
      [{:rect, x, y, cell, cell, 0xFFFFFF} | heads(rest, arena, layout)]
    else
      heads(rest, arena, layout)
    end
  end

  defp trails(%{occupied: {width, height, bytes}, arena: arena}, %{x: x, y: y, cell: cell}) do
    left = Map.fetch!(arena, :left)
    top = Map.fetch!(arena, :top)
    w = Map.fetch!(arena, :right) - left + 1
    h = Map.fetch!(arena, :bottom) - top + 1

    [
      {:scaled_cropped_image, x + left * cell, y + top * cell, w * cell, h * cell, :transparent, left, top, cell, cell, [],
       {:rgba8888, width, height, bytes}}
    ]
  end

  defp trails(game, layout) do
    runs =
      Map.fetch!(game, :occupied)
      |> Enum.filter(fn {position, _id} -> Arena.contains?(Map.fetch!(game, :arena), position) end)
      |> Enum.map(fn {{x, y}, id} -> {y, x, id} end)
      |> :lists.sort()
      |> Enum.reduce([], &join_run/2)

    for {row, column, id, count} <- runs do
      {x, y} = point({column, row}, layout)
      {:rect, x, y, count * Map.fetch!(layout, :cell), Map.fetch!(layout, :cell), color(id)}
    end
  end

  defp join_run({row, column, id}, [{row, start, id, count} | rest]) when column == start + count,
    do: [{row, start, id, count + 1} | rest]

  defp join_run({row, column, id}, runs), do: [{row, column, id, 1} | runs]

  defp frame(%{left: left, top: top, right: right, bottom: bottom}, %{cell: cell, x: ox, y: oy}, color) do
    x = ox + left * cell
    y = oy + top * cell
    w = (right - left + 1) * cell
    h = (bottom - top + 1) * cell

    [
      {:rect, x - 1, y - 1, w + 2, 1, color},
      {:rect, x - 1, y + h, w + 2, 1, color},
      {:rect, x - 1, y, 1, h, color},
      {:rect, x + w, y, 1, h, color}
    ]
  end

  defp background(arena, layout) do
    {x, y} = point({Map.fetch!(arena, :left), Map.fetch!(arena, :top)}, layout)

    {:rect, x, y, (Map.fetch!(arena, :right) - Map.fetch!(arena, :left) + 1) * Map.fetch!(layout, :cell),
     (Map.fetch!(arena, :bottom) - Map.fetch!(arena, :top) + 1) * Map.fetch!(layout, :cell), @board}
  end

  defp point({x, y}, %{x: ox, y: oy, cell: cell}), do: {ox + x * cell, oy + y * cell}
end
