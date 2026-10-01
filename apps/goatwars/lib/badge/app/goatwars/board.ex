defmodule Badge.App.Goatwars.Board do
  @moduledoc "Fixed-size opaque RGBA board; map storage remains available for headless play."

  def new(%{width: width, height: height}, occupied) do
    board = {width, height, :binary.copy(<<0, 0, 32, 255>>, width * height)}
    Enum.reduce(occupied, board, fn {position, id}, board -> put(board, position, id) end)
  end

  def get(board, position) when is_map(board), do: Map.get(board, position)

  def get({width, height, bytes}, {x, y}) when x >= 0 and y >= 0 and x < width and y < height do
    offset = (y * width + x) * 4

    case bytes do
      <<_::binary-size(offset), 0, 0, 255, 255, _::binary>> -> 1
      <<_::binary-size(offset), 255, 0, 0, 255, _::binary>> -> 2
      <<_::binary-size(offset), 0, 255, 0, 255, _::binary>> -> 3
      <<_::binary-size(offset), 255, 255, 0, 255, _::binary>> -> 4
      _ -> nil
    end
  end

  def get(_, _), do: nil

  def has?(board, position), do: get(board, position) != nil
  def put(board, position, id) when is_map(board), do: Map.put(board, position, id)

  def put({width, height, bytes} = board, {x, y} = position, id)
      when x >= 0 and y >= 0 and x < width and y < height do
    if get(board, position) == id do
      board
    else
      offset = (y * width + x) * 4
      <<prefix::binary-size(offset), _::32, suffix::binary>> = bytes
      {width, height, <<prefix::binary, pixel(id)::binary, suffix::binary>>}
    end
  end

  def put(board, _, _), do: board

  def delete(board, position) when is_map(board), do: Map.delete(board, position)
  def delete(board, position), do: put(board, position, nil)

  defp pixel(1), do: <<0, 0, 255, 255>>
  defp pixel(2), do: <<255, 0, 0, 255>>
  defp pixel(3), do: <<0, 255, 0, 255>>
  defp pixel(4), do: <<255, 255, 0, 255>>
  defp pixel(nil), do: <<0, 0, 32, 255>>
end
