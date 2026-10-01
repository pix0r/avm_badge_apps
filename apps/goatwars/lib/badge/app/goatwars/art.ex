defmodule Badge.App.Goatwars.Art do
  @moduledoc "Compact placeholder pixel artwork for the GoatWars screens."

  @palette {
    <<0, 0, 0, 0>>,
    <<255, 244, 204, 255>>,
    <<93, 226, 180, 255>>,
    <<255, 122, 144, 255>>,
    <<22, 13, 34, 255>>,
    <<107, 88, 136, 255>>,
    <<187, 160, 111, 255>>,
    <<255, 255, 241, 255>>,
    <<65, 111, 102, 255>>,
    <<77, 43, 99, 255>>,
    <<160, 255, 214, 255>>,
    <<224, 198, 145, 255>>,
    <<55, 33, 76, 255>>,
    <<189, 167, 255, 255>>,
    <<255, 172, 183, 255>>,
    <<255, 209, 102, 255>>
  }

  @assets (fn ->
             rect = fn canvas, x, y, w, h, color ->
               Enum.reduce(y..(y + h - 1), canvas, fn py, canvas ->
                 Enum.reduce(x..(x + w - 1), canvas, fn px, canvas ->
                   Map.put(canvas, {px, py}, color)
                 end)
               end)
             end

             ellipse = fn canvas, cx, cy, rx, ry, color ->
               Enum.reduce((cy - ry)..(cy + ry), canvas, fn y, canvas ->
                 Enum.reduce((cx - rx)..(cx + rx), canvas, fn x, canvas ->
                   if (x - cx) * (x - cx) * ry * ry + (y - cy) * (y - cy) * rx * rx <= rx * rx * ry * ry,
                     do: Map.put(canvas, {x, y}, color),
                     else: canvas
                 end)
               end)
             end

             pack = fn canvas, width, height ->
               for y <- 0..(height - 1), x <- 0..(div(width, 2) - 1), into: <<>> do
                 <<Map.get(canvas, {x * 2, y}, 0)::4, Map.get(canvas, {x * 2 + 1, y}, 0)::4>>
               end
             end

             goat = %{}
             goat = rect.(goat, 1, 53, 27, 2, 3)
             goat = rect.(goat, 0, 56, 25, 2, 2)
             goat = rect.(goat, 7, 59, 17, 1, 8)
             goat = ellipse.(goat, 26, 53, 12, 10, 4)
             goat = ellipse.(goat, 74, 53, 12, 10, 4)
             goat = ellipse.(goat, 26, 53, 9, 8, 2)
             goat = ellipse.(goat, 74, 53, 9, 8, 2)
             goat = ellipse.(goat, 26, 53, 6, 5, 4)
             goat = ellipse.(goat, 74, 53, 6, 5, 4)
             goat = ellipse.(goat, 26, 53, 2, 2, 10)
             goat = ellipse.(goat, 74, 53, 2, 2, 10)
             goat = rect.(goat, 22, 42, 58, 7, 8)
             goat = rect.(goat, 32, 40, 32, 4, 2)
             goat = rect.(goat, 36, 44, 30, 2, 10)
             goat = rect.(goat, 45, 47, 21, 3, 2)
             goat = rect.(goat, 70, 35, 5, 8, 2)
             goat = rect.(goat, 67, 34, 9, 2, 10)
             goat = rect.(goat, 77, 40, 6, 3, 2)
             goat = rect.(goat, 28, 37, 25, 4, 4)
             goat = ellipse.(goat, 41, 30, 14, 9, 6)
             goat = ellipse.(goat, 41, 28, 13, 8, 1)
             goat = rect.(goat, 28, 26, 6, 10, 1)
             goat = rect.(goat, 24, 23, 7, 3, 7)
             goat = rect.(goat, 22, 21, 4, 3, 1)
             goat = rect.(goat, 34, 34, 5, 7, 11)
             goat = rect.(goat, 34, 39, 10, 3, 4)
             goat = rect.(goat, 47, 30, 6, 9, 1)
             goat = rect.(goat, 50, 36, 12, 4, 1)
             goat = rect.(goat, 59, 34, 5, 5, 4)
             goat = rect.(goat, 50, 20, 10, 9, 1)
             goat = rect.(goat, 53, 15, 15, 10, 1)
             goat = rect.(goat, 64, 20, 10, 6, 1)
             goat = rect.(goat, 55, 14, 9, 3, 7)
             goat = rect.(goat, 50, 16, 6, 3, 11)
             goat = rect.(goat, 47, 14, 5, 3, 1)
             goat = rect.(goat, 55, 8, 3, 8, 6)
             goat = rect.(goat, 53, 5, 3, 5, 6)
             goat = rect.(goat, 51, 2, 3, 4, 11)
             goat = rect.(goat, 62, 7, 3, 9, 6)
             goat = rect.(goat, 65, 4, 3, 5, 11)
             goat = rect.(goat, 67, 1, 2, 4, 7)
             goat = rect.(goat, 64, 18, 2, 2, 4)
             goat = rect.(goat, 71, 23, 3, 2, 6)
             goat = rect.(goat, 61, 25, 5, 4, 11)
             goat = rect.(goat, 61, 28, 3, 3, 1)
             goat = rect.(goat, 30, 27, 11, 2, 7)

             letters = [
               ["01111", "11000", "11000", "11011", "11001", "11001", "01111"],
               ["01110", "11011", "11011", "11011", "11011", "11011", "01110"],
               ["01110", "11011", "11011", "11111", "11011", "11011", "11011"],
               ["11111", "00110", "00110", "00110", "00110", "00110", "00110"],
               ["11011", "11011", "11011", "11011", "11111", "11111", "01010"],
               ["01110", "11011", "11011", "11111", "11011", "11011", "11011"],
               ["11110", "11011", "11011", "11110", "11100", "11010", "11011"],
               ["01111", "11000", "11000", "01110", "00011", "00011", "11110"]
             ]

             draw_logo = fn canvas, dx, dy, color ->
               Enum.reduce(Enum.with_index(letters), canvas, fn {rows, i}, canvas ->
                 Enum.reduce(Enum.with_index(rows), canvas, fn {row, y}, canvas ->
                   Enum.reduce(Enum.with_index(:binary.bin_to_list(row)), canvas, fn {pixel, x}, canvas ->
                     if pixel == ?1,
                       do: rect.(canvas, 9 + i * 16 + x * 3 + div(6 - y, 3) + dx, 3 + y * 3 + dy, 3, 3, color),
                       else: canvas
                   end)
                 end)
               end)
             end

             logo = draw_logo.(%{}, 3, 4, 3)
             logo = draw_logo.(logo, -2, 2, 2)
             logo = draw_logo.(logo, 0, 0, 1)

             rle = fn packed ->
               bytes = packed |> :binary.bin_to_list() |> List.to_tuple()
               size = tuple_size(bytes)

               choices =
                 Enum.reduce((size - 1)..0//-1, %{size => {0, :end, 0}}, fn index, choices ->
                   max_count = min(128, size - index)
                   value = elem(bytes, index)

                   repeated =
                     Enum.reduce_while(1..max_count, 0, fn count, _ ->
                       if elem(bytes, index + count - 1) == value, do: {:cont, count}, else: {:halt, count - 1}
                     end)

                   literals =
                     for count <- 1..max_count do
                       {cost, _, _} = Map.fetch!(choices, index + count)
                       {cost + count + 1, :literal, count}
                     end

                   runs =
                     for count <- 1..repeated do
                       {cost, _, _} = Map.fetch!(choices, index + count)
                       {cost + 2, :run, count}
                     end

                   Map.put(choices, index, Enum.min_by(literals ++ runs, &elem(&1, 0)))
                 end)

               encode = fn encode, index ->
                 case Map.fetch!(choices, index) do
                   {_, :end, _} ->
                     []

                   {_, :run, count} ->
                     [<<1::1, count - 1::7, elem(bytes, index)>> | encode.(encode, index + count)]

                   {_, :literal, count} ->
                     [<<0::1, count - 1::7>>, :binary.part(packed, index, count) | encode.(encode, index + count)]
                 end
               end

               :erlang.list_to_binary(encode.(encode, 0))
             end

             {rle.(pack.(goat, 96, 64)), rle.(pack.(logo, 144, 32))}
           end).()

  def load do
    {goat, logo} = @assets
    %{goat: {:rgba8888, 96, 64, decode_rle(goat, @palette)}, logo: {:rgba8888, 144, 32, decode_rle(logo, @palette)}}
  end

  def stored_bytes do
    {goat, logo} = @assets
    byte_size(goat) + byte_size(logo) + 64
  end

  @doc "Expand RLE headers: high bit repeats a byte; low seven bits store count minus one."
  def decode_rle(runs, palette), do: decode_runs(runs, palette, <<>>, [])

  defp decode_runs(<<>>, palette, buffer, chunks) do
    decode_chunks(buffer, palette, chunks)
  end

  defp decode_runs(<<1::1, count::7, value, rest::binary>>, palette, buffer, chunks) do
    decode_run(count + 1, value, rest, palette, buffer, chunks)
  end

  defp decode_runs(<<0::1, count::7, bytes::binary>>, palette, buffer, chunks) do
    size = count + 1
    <<literal::binary-size(size), rest::binary>> = bytes
    decode_literal(literal, rest, palette, buffer, chunks)
  end

  defp decode_literal(literal, rest, palette, <<buffer::binary-size(32)>>, chunks) do
    bytes = :erlang.list_to_binary(decode_chunk(buffer, palette))
    decode_literal(literal, rest, palette, <<>>, [bytes | chunks])
  end

  defp decode_literal(<<>>, rest, palette, buffer, chunks) do
    decode_runs(rest, palette, buffer, chunks)
  end

  defp decode_literal(literal, rest, palette, buffer, chunks) do
    room = 32 - byte_size(buffer)
    size = byte_size(literal)
    take = if size < room, do: size, else: room
    <<bytes::binary-size(take), remaining::binary>> = literal
    decode_literal(remaining, rest, palette, <<buffer::binary, bytes::binary>>, chunks)
  end

  defp decode_run(count, value, rest, palette, <<buffer::binary-size(32)>>, chunks) do
    bytes = :erlang.list_to_binary(decode_chunk(buffer, palette))
    decode_run(count, value, rest, palette, <<>>, [bytes | chunks])
  end

  defp decode_run(0, _value, rest, palette, buffer, chunks) do
    decode_runs(rest, palette, buffer, chunks)
  end

  defp decode_run(count, value, rest, palette, buffer, chunks) do
    room = 32 - byte_size(buffer)
    take = if count < room, do: count, else: room
    bytes = :erlang.list_to_binary(:lists.duplicate(take, value))
    decode_run(count - take, value, rest, palette, <<buffer::binary, bytes::binary>>, chunks)
  end

  defp decode_chunks(<<>>, _palette, chunks), do: :erlang.list_to_binary(:lists.reverse(chunks))

  defp decode_chunks(<<chunk::binary-size(32), rest::binary>>, palette, chunks) do
    bytes = :erlang.list_to_binary(decode_chunk(chunk, palette))
    decode_chunks(rest, palette, [bytes | chunks])
  end

  defp decode_chunks(chunk, palette, chunks) do
    bytes = :erlang.list_to_binary(decode_chunk(chunk, palette))
    decode_chunks(<<>>, palette, [bytes | chunks])
  end

  defp decode_chunk(<<>>, _palette), do: []

  defp decode_chunk(<<high::4, low::4, rest::binary>>, palette) do
    [elem(palette, high), elem(palette, low) | decode_chunk(rest, palette)]
  end
end
