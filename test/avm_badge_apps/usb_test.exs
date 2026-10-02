defmodule AvmBadgeApps.UsbTest do
  use ExUnit.Case, async: false
  alias AvmBadgeApps.Usb

  setup do
    dir = Path.join(System.tmp_dir!(), "badge-usb-" <> Base.encode16(:crypto.strong_rand_bytes(8)))
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "the USB home grid preserves firmware pages and opens GoatWars offline" do
    source = File.read!(Path.expand("../avm_badge/lib/badge/pages.ex"))
    generated = Usb.pages_source(source, AvmBadgeApps.UsbTest.Pages)
    Code.compile_string(generated)
    module = AvmBadgeApps.UsbTest.Pages
    Badge.Store.Installed.set([])
    pages = apply(module, :all, [])
    original = Badge.Pages.all()
    assert pages == original ++ [Badge.App.Goatwars.Page]
    assert Enum.at(pages, 15) == Badge.Page.Store
    assert apply(module, :for_key, [:clover, 2]) == Badge.App.Goatwars.Page
    assert apply(module, :screens, []) == 3
    page = apply(module, :for_key, [:clover, 2])
    state = page.init()
    assert state.match.replay == []
  end

  test "USB packs retain startup and assets without duplicate page modules", %{dir: dir} do
    inputs = fixtures(dir)
    paths = Usb.build!(inputs, Path.join(dir, "out"))
    assert File.read!(Path.join(dir, "out/navigation.txt")) ==
             "On Home, press Right 2 times, then the clover key to open GoatWars.\n"
    inspected = Path.join(dir, "inspect.avm")
    # Normalize metadata flags for the legacy host archive inspector.
    original = File.read!(paths.firmware)
    assert :binary.match(original, "avm_badge/priv/application.bin") != :nomatch
    name = "avm_badge/priv/application.bin"
    File.write!(inspected, :binary.replace(original, <<2::32, 0::32, name::binary>>, <<0::32, 0::32, name::binary>>))
    firmware = :packbeam_api.list(to_charlist(inspected))
    names = Enum.map(firmware, &:packbeam_api.get_element_name/1)
    assert Enum.count(names, &(&1 == ~c"Elixir.Badge.Pages.beam")) == 1
    assert ~c"Elixir.UsbFixtureBoot.beam" in names
    assert Enum.any?(firmware, &:packbeam_api.is_entrypoint/1)
    assets = :packbeam_api.list(to_charlist(paths.assets))
    names = Enum.map(assets, &:packbeam_api.get_element_name/1)
    assert ~c"assets/priv/logo/test.rgba" in names
    assert ~c"Elixir.Badge.App.Goatwars.Page.beam" in names
    assert File.stat!(paths.firmware).size <= 671_744
    assert File.stat!(paths.assets).size <= 262_144
  end

  test "USB omits host Mix tasks and preserves runtime sections and startup metadata", %{dir: dir} do
    inputs = fixtures(dir)
    [{host, beam}] = Code.compile_string("defmodule Mix.Tasks.UsbHostFixture do; def run(_), do: :host_only; end")
    host_path = Path.join(dir, "#{host}.beam")
    File.write!(host_path, beam)
    with_host = Path.join(dir, "with-host.avm")
    :ok = ExAtomVM.PackBEAM.make_avm([{inputs.firmware, :avm}, {host_path, :beam}], with_host)
    inputs = %{inputs | firmware: with_host}
    assert ~c"Elixir.Mix.Tasks.UsbHostFixture.beam" in packed_names(File.read!(with_host))

    paths = Usb.build!(inputs, Path.join(dir, "host-filtered"))
    names = packed_names(File.read!(paths.firmware))
    refute Enum.any?(names, &List.starts_with?(&1, ~c"Elixir.Mix.Tasks."))
    assert Enum.count(names, &(&1 == ~c"Elixir.Badge.Pages.beam")) == 1

    for name <- ["Elixir.UsbFixtureBoot.beam", "avm_badge/priv/application.bin"] do
      assert packed_section_for(paths.firmware, name) == packed_section_for(with_host, name)
    end

    <<_::32, flags::32, _::binary>> = packed_section_for(paths.firmware, "Elixir.UsbFixtureBoot.beam")
    assert flags == 1
  end

  test "USB splits game modules across both packs when assets have little room", %{dir: dir} do
    inputs = fixtures(dir)
    path = Path.join(dir, "assets/priv/padding.bin")
    File.write!(path, :binary.copy(<<0>>, 210_000))

    File.cd!(dir, fn ->
      :ok = :packbeam_api.create(to_charlist(inputs.assets), [~c"assets/priv/padding.bin"], %{lib: true})
    end)

    assert File.stat!(inputs.assets).size + File.stat!(inputs.game).size > 262_144
    paths = Usb.build!(inputs, Path.join(dir, "split"))
    inspected = Path.join(dir, "split-inspect.avm")
    name = "avm_badge/priv/application.bin"
    bytes = File.read!(paths.firmware)
    File.write!(inspected, :binary.replace(bytes, <<2::32, 0::32, name::binary>>, <<0::32, 0::32, name::binary>>))

    names =
      for pack <- [inspected, paths.assets], section <- :packbeam_api.list(to_charlist(pack)), do: :packbeam_api.get_element_name(section)

    modules = AvmBadgeApps.Pack.beams!(Mix.Project.compile_path(), "goatwars")

    for module <- modules do
      name = module |> Path.basename() |> to_charlist()
      assert Enum.count(names, &(&1 == name)) == 1
    end

    assert File.stat!(paths.firmware).size <= 671_744
    assert File.stat!(paths.assets).size <= 262_144
  end

  test "USB chooses the smallest sufficient subset when a greedy prefix overflows firmware", %{dir: dir} do
    inputs = fixtures(dir)
    baseline = Usb.build!(inputs, Path.join(dir, "baseline"))
    padding_size = 671_744 - 7_000 - File.stat!(baseline.firmware).size
    ending = <<0::32, 0::32, 0::32, "end", 0>>
    firmware = File.read!(inputs.firmware)
    prefix = binary_part(firmware, 0, byte_size(firmware) - 16)
    File.write!(inputs.firmware, [prefix, packed_section(padding_size, "firmware-padding"), ending])
    <<header::binary-size(24), _::binary>> = File.read!(inputs.game)
    sections = for size <- [6_000, 4_500, 2_000, 1_000], do: packed_section(size, "synthetic-#{size}.beam")
    File.write!(inputs.game, [header, sections, ending])
    File.write!(inputs.assets, [header, packed_section(255_604, "assets-padding"), ending])

    paths = Usb.build!(inputs, Path.join(dir, "tight"))
    assert File.stat!(paths.firmware).size == 671_744
    assert File.stat!(paths.assets).size == 262_144

    for {pack, expected} <- [
          {paths.firmware, [~c"synthetic-6000.beam", ~c"synthetic-1000.beam"]},
          {paths.assets, [~c"synthetic-4500.beam", ~c"synthetic-2000.beam"]}
        ] do
      names = packed_names(File.read!(pack))
      assert Enum.filter(names, &List.starts_with?(&1, ~c"synthetic-")) == expected
      bytes = File.read!(pack)
      assert binary_part(bytes, byte_size(bytes) - 16, 16) == ending
      assert length(:binary.matches(bytes, ending)) == 1
    end
  end

  test "oversized assets fail before an installable output is produced", %{dir: dir} do
    inputs = fixtures(dir)
    File.write!(inputs.assets, File.read!(inputs.assets) <> :binary.copy(<<0>>, 262_144))
    output = Path.join(dir, "out")
    assert_raise Mix.Error, ~r/assets.*partition/, fn -> Usb.build!(inputs, output) end
    refute File.exists?(Path.join(output, "firmware.avm"))
    refute File.exists?(Path.join(output, "assets.avm"))
  end

  defp packed_section_for(path, name) do
    <<_::binary-size(24), sections::binary>> = File.read!(path)
    find_section(sections, name)
  end

  defp find_section(<<0::32, 0::32, 0::32, "end", 0>>, name), do: flunk("missing section #{name}")

  defp find_section(<<size::32, _::binary>> = bytes, name) do
    <<section::binary-size(size), rest::binary>> = bytes
    <<_::binary-size(12), named::binary>> = section
    [actual | _] = :binary.split(named, <<0>>)
    if actual == name, do: section, else: find_section(rest, name)
  end

  defp packed_names(<<_::binary-size(24), sections::binary>>), do: section_names(sections)

  defp section_names(<<0::32, 0::32, 0::32, "end", 0>>), do: []

  defp section_names(<<size::32, _::binary>> = bytes) do
    <<section::binary-size(size), rest::binary>> = bytes
    <<_::binary-size(12), named::binary>> = section
    [name | _] = :binary.split(named, <<0>>)
    [to_charlist(name) | section_names(rest)]
  end

  defp packed_section(size, name) do
    prefix = <<size::32, 0::32, 0::32, name::binary, 0>>
    prefix <> :binary.copy(<<0>>, size - byte_size(prefix))
  end

  defp fixtures(dir) do
    source = File.read!(Path.expand("../avm_badge/lib/badge/pages.ex"))
    {boot, binary} = hd(Code.compile_string("defmodule UsbFixtureBoot do; def start, do: :ok; end"))
    boot_path = Path.join(dir, "#{boot}.beam")
    File.write!(boot_path, binary)
    pages_path = Path.join(dir, "Elixir.Badge.Pages.beam")
    File.write!(pages_path, File.read!(:code.which(Badge.Pages)))
    metadata = Path.join(dir, "application.bin")
    File.write!(metadata, :erlang.term_to_binary({:application, :badge, []}))
    main = Path.join(dir, "base.avm")

    :ok =
      ExAtomVM.PackBEAM.make_avm(
        [{boot_path, :beam_start}, {pages_path, :beam}, {metadata, [file: "avm_badge/priv/application.bin"]}],
        main
      )

    logo = Path.join(dir, "assets/priv/logo/test.rgba")
    File.mkdir_p!(Path.dirname(logo))
    File.write!(logo, <<1, 2, 3, 4>>)
    assets = Path.join(dir, "base-assets.avm")

    File.cd!(dir, fn ->
      :ok = :packbeam_api.create(to_charlist(assets), [~c"assets/priv/logo/test.rgba"], %{lib: true})
    end)

    game = Path.join(dir, "goatwars.avm")
    beams = AvmBadgeApps.Pack.beams!(Mix.Project.compile_path(), "goatwars")
    :ok = ExAtomVM.PackBEAM.make_avm(Enum.map(beams, &{&1, :beam}), game)
    %{firmware: main, assets: assets, game: game, pages_source: source}
  end
end
