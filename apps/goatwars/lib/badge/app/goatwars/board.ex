defmodule Badge.App.Goatwars.Board do
  @moduledoc "Fixed-size opaque RGBA board; map storage remains available for headless play."

  @compile :no_line_info

  def new(%{width: width, height: height}, occupied) do
    board = {width, height, :binary.copy(pixel(nil), width * height)}
    Enum.reduce(occupied, board, fn {position, id}, board -> put(board, position, id) end)
  end

  def get(board, position) when is_map(board), do: Map.get(board, position)

  def get({width, height, bytes}, {x, y}) when is_binary(bytes) and x >= 0 and y >= 0 and x < width and y < height do
    offset = (y * width + x) * 4

    if byte_size(bytes) >= offset + 4 do
      case :binary.at(bytes, offset) do
        200 -> decode(bytes, offset, 64, 255, 1)
        0 -> decode(bytes, offset, 255, 136, 2)
        255 -> decode(bytes, offset, 40, 92, 3)
        112 -> decode(bytes, offset, 64, 255, 4)
        _ -> nil
      end
    else
      nil
    end
  end

  def get(_, _), do: nil

  defp decode(bytes, offset, green, blue, id) do
    if :binary.at(bytes, offset + 1) == green and :binary.at(bytes, offset + 2) == blue and :binary.at(bytes, offset + 3) == 255,
      do: id,
      else: nil
  end

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

  @doc "Clears a group of cells with one bitmap copy."
  def delete_many(board, []), do: board

  def delete_many(board, cells) when is_map(board),
    do: Enum.reduce(cells, board, fn cell, board -> Map.delete(board, cell) end)

  def delete_many({width, height, bytes} = board, cells) do
    offsets = for {x, y} = cell <- cells, get(board, cell) != nil, do: (y * width + x) * 4

    case :lists.usort(offsets) do
      [] -> board
      offsets -> {width, height, clear_chunks(bytes, offsets, pixel(nil), 0, [])}
    end
  end

  defp clear_chunks(bytes, [], _empty, cursor, chunks),
    do: :erlang.iolist_to_binary(:lists.reverse([:binary.part(bytes, cursor, byte_size(bytes) - cursor) | chunks]))

  defp clear_chunks(bytes, [offset | rest], empty, cursor, chunks) do
    prefix = :binary.part(bytes, cursor, offset - cursor)
    clear_chunks(bytes, rest, empty, offset + 4, [empty, prefix | chunks])
  end

  defp pixel(id) do
    color =
      case id do
        1 -> 0xC840FF
        2 -> 0x00FF88
        3 -> 0xFF285C
        4 -> 0x7040FF
        nil -> 0x3D175A
      end
    <<color::24, 255>>
  end
end
