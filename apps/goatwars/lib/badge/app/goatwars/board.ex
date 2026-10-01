defmodule Badge.App.Goatwars.Board do
  @moduledoc "Fixed-size opaque RGBA board; map storage remains available for headless play."

  def new(%{width: width, height: height}, occupied) do
    board = {width, height, :binary.copy(pixel(nil), width * height)}
    Enum.reduce(occupied, board, fn {position, id}, board -> put(board, position, id) end)
  end

  def get(board, position) when is_map(board), do: Map.get(board, position)

  def get({width, height, bytes}, {x, y}) when x >= 0 and y >= 0 and x < width and y < height do
    offset = (y * width + x) * 4

    case bytes do
      <<_::binary-size(offset), color::24, 255, _::binary>> ->
        case color do
          0xFFD166 -> 1
          0x5DE2B4 -> 2
          0xFF7A90 -> 3
          0xBDA7FF -> 4
          _ -> nil
        end

      _ ->
        nil
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

  @doc "Clears a group of cells with one bitmap copy."
  def delete_many(board, []), do: board

  def delete_many(board, cells) when is_map(board),
    do: Enum.reduce(cells, board, fn cell, board -> Map.delete(board, cell) end)

  def delete_many({width, height, bytes} = board, cells) do
    offsets = for {x, y} = cell <- cells, get(board, cell) != nil, do: (y * width + x) * 4

    case :lists.usort(offsets) do
      [] -> board
      offsets -> {width, height, clear_chunks(bytes, offsets, 0, [])}
    end
  end

  defp clear_chunks(bytes, [], cursor, chunks),
    do: :erlang.iolist_to_binary(:lists.reverse([:binary.part(bytes, cursor, byte_size(bytes) - cursor) | chunks]))

  defp clear_chunks(bytes, [offset | rest], cursor, chunks) do
    prefix = :binary.part(bytes, cursor, offset - cursor)
    clear_chunks(bytes, rest, offset + 4, [pixel(nil), prefix | chunks])
  end

  defp pixel(1), do: <<255, 209, 102, 255>>
  defp pixel(2), do: <<93, 226, 180, 255>>
  defp pixel(3), do: <<255, 122, 144, 255>>
  defp pixel(4), do: <<189, 167, 255, 255>>
  defp pixel(nil), do: <<36, 19, 50, 255>>
end
