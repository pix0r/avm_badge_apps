defmodule Badge.App.Goatwars.ArtTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.Art

  test "decodes high nibble first and preserves palette alpha" do
    palette =
      {<<0, 0, 0, 0>>, <<11, 22, 33, 255>>, <<44, 55, 66, 128>>, <<77, 88, 99, 1>>, <<4, 4, 4, 4>>, <<5, 5, 5, 5>>, <<6, 6, 6, 6>>,
       <<7, 7, 7, 7>>, <<8, 8, 8, 8>>, <<9, 9, 9, 9>>, <<10, 10, 10, 10>>, <<11, 11, 11, 11>>, <<12, 12, 12, 12>>, <<13, 13, 13, 13>>,
       <<14, 14, 14, 14>>, <<15, 15, 15, 15>>}

    assert Art.decode_rle(<<1, 0x12, 0x30>>, palette) ==
             <<11, 22, 33, 255, 44, 55, 66, 128, 77, 88, 99, 1, 0, 0, 0, 0>>

    assert Art.decode_rle(<<>>, palette) == <<>>
  end

  test "expands runs across chunk boundaries without reversing transparent pixels" do
    palette =
      List.to_tuple(
        [<<0, 0, 0, 0>>, <<11, 22, 33, 255>>, <<44, 55, 66, 128>>] ++
          List.duplicate(<<255, 255, 255, 255>>, 13)
      )

    expected =
      :binary.copy(<<11, 22, 33, 255, 44, 55, 66, 128>>, 33) <>
        <<0, 0, 0, 0, 11, 22, 33, 255>> <>
        :binary.copy(<<0, 0, 0, 0, 0, 0, 0, 0>>, 255) <>
        :binary.copy(<<44, 55, 66, 128, 0, 0, 0, 0>>, 35)

    fixture = <<160, 0x12, 0, 0x01, 255, 0x00, 254, 0x00, 0, 0x20, 33>> <> :binary.copy(<<0x20>>, 34)
    assert Art.decode_rle(fixture, palette) == expected
    assert Art.decode_rle(<<>>, palette) == <<>>
  end

  test "compression preserves the themed artwork pixels exactly" do
    art = Art.load()
    {:rgba8888, 96, 64, goat} = Map.fetch!(art, :goat)
    {:rgba8888, 144, 32, logo} = Map.fetch!(art, :logo)

    assert Base.encode16(:crypto.hash(:sha256, goat)) ==
             "30DC209599A93DE36F2B80F408FAECFC2DDF89BE3A2124BD0A694CF9DACCDF2D"

    assert Base.encode16(:crypto.hash(:sha256, logo)) ==
             "365F4480A63DA379D72BFC4887605B6B3416192E1918ADFF0FD422731357543C"
  end

  test "loads complete RGBA textures at badge artwork dimensions" do
    art = Art.load()
    assert {:rgba8888, 96, 64, goat} = Map.fetch!(art, :goat)
    assert {:rgba8888, 144, 32, logo} = Map.fetch!(art, :logo)
    assert byte_size(goat) == 24_576
    assert byte_size(logo) == 18_432
  end

  test "art keeps transparency, cream, mint and coral colour pixels" do
    art = Art.load()

    for key <- [:goat, :logo] do
      {:rgba8888, _, _, pixels} = Map.fetch!(art, key)
      colors = for <<r, g, b, a <- pixels>>, into: MapSet.new(), do: {r, g, b, a}
      assert MapSet.member?(colors, {0, 0, 0, 0})
      assert MapSet.member?(colors, {255, 244, 204, 255})
      assert MapSet.member?(colors, {93, 226, 180, 255})
      assert MapSet.member?(colors, {255, 122, 144, 255})
      assert Enum.all?(colors, fn {_, _, _, a} -> a in [0, 255] end)
    end
  end

  test "stored palette and packed artwork fit the asset budget" do
    assert Art.stored_bytes() > 0
    assert Art.stored_bytes() <= 2_600
  end
end
