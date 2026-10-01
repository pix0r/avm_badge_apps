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

  defp decode_runs(<<>>, _palette, buffer, chunks),
    do: :erlang.iolist_to_binary(:lists.reverse([buffer | chunks]))

  defp decode_runs(runs, palette, buffer, chunks) when byte_size(buffer) >= 512,
    do: decode_runs(runs, palette, <<>>, [buffer | chunks])

  defp decode_runs(<<1::1, count::7, high::4, low::4, rest::binary>>, palette, buffer, chunks) do
    pair = <<elem(palette, high)::binary, elem(palette, low)::binary>>
    bytes = :binary.copy(pair, count + 1)
    decode_runs(rest, palette, <<buffer::binary, bytes::binary>>, chunks)
  end

  defp decode_runs(<<0::1, count::7, bytes::binary>>, palette, buffer, chunks) do
    size = count + 1
    <<literal::binary-size(size), rest::binary>> = bytes
    expanded = :erlang.iolist_to_binary(decode_chunk(literal, palette))
    decode_runs(rest, palette, <<buffer::binary, expanded::binary>>, chunks)
  end

  defp decode_chunk(<<>>, _palette), do: []

  defp decode_chunk(<<high::4, low::4, rest::binary>>, palette) do
    [elem(palette, high), elem(palette, low) | decode_chunk(rest, palette)]
  end
end
