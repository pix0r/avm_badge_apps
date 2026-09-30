defmodule Badge.App.Goatwars.Render.Layout do
  @moduledoc "Pixel geometry for a badge-sized arena."
  def new(x, y, cell), do: %{x: x, y: y, cell: cell}
end
