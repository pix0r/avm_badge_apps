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

  test "compression preserves the detailed goat and angular logo pixels exactly" do
    art = Art.load()
    {:rgba8888, 96, 64, goat} = Map.fetch!(art, :goat)
    {:rgba8888, 144, 40, logo} = Map.fetch!(art, :logo)

    assert Base.encode16(:crypto.hash(:sha256, goat)) ==
             "513F8C6166E50E2E18F4BB54C88628B62AE1D5D3D2F2F557898C34864A64AAE9"

    assert Base.encode16(:crypto.hash(:sha256, logo)) ==
             "F18B4D03C5C5A22A173BAF38416FE2673549C97A13265783E7105C001763EE5C"
  end

  test "loads complete RGBA textures at badge artwork dimensions" do
    art = Art.load()
    assert {:rgba8888, 96, 64, goat} = Map.fetch!(art, :goat)
    assert {:rgba8888, 144, 40, logo} = Map.fetch!(art, :logo)
    assert byte_size(goat) == 24_576
    assert byte_size(logo) == 23_040
  end

  test "art keeps transparency, cream, cyan and coral colour pixels" do
    art = Art.load()

    for key <- [:goat, :logo] do
      {:rgba8888, _, _, pixels} = Map.fetch!(art, key)
      colors = for <<r, g, b, a <- pixels>>, into: MapSet.new(), do: {r, g, b, a}
      assert MapSet.member?(colors, {0, 0, 0, 0})
      assert MapSet.member?(colors, {255, 244, 204, 255})
      assert MapSet.member?(colors, {0, 229, 255, 255})
      assert MapSet.member?(colors, {255, 122, 144, 255})
      assert Enum.all?(colors, fn {_, _, _, a} -> a in [0, 255] end)
    end
  end

  test "artwork loading stays within a small decode work budget" do
    {:reductions, before} = Process.info(self(), :reductions)
    Enum.each(1..100, fn _ -> Art.load() end)
    {:reductions, after_count} = Process.info(self(), :reductions)
    assert div(after_count - before, 100) < 12000
  end

  test "stored palette and packed artwork fit the asset budget" do
    assert Art.stored_bytes() > 0
    assert Art.stored_bytes() <= 3_800
  end
end
