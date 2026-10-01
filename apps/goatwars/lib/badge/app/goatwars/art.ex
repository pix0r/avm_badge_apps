defmodule Badge.App.Goatwars.Art do
  @moduledoc "Compact detailed pixel artwork for the GoatWars screens."

  @asset_dir Path.expand("../../../../assets", __DIR__)
  @goat_path Path.join(@asset_dir, "goat.rle")
  @logo_path Path.join(@asset_dir, "logo.rle")
  @palette_path Path.join(@asset_dir, "palette.rgba")
  @external_resource @goat_path
  @external_resource @logo_path
  @external_resource @palette_path
  @palette List.to_tuple(for <<pixel::binary-size(4) <- File.read!(@palette_path)>>, do: pixel)
  @assets {File.read!(@goat_path), File.read!(@logo_path)}
  @stored_bytes byte_size(elem(@assets, 0)) + byte_size(elem(@assets, 1)) + 64

  def load do
    {goat, logo} = @assets
    %{goat: {:rgba8888, 96, 64, decode_rle(goat, @palette)}, logo: {:rgba8888, 144, 40, decode_rle(logo, @palette)}}
  end

  def stored_bytes, do: @stored_bytes

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
