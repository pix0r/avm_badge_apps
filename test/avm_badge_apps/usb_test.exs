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
    assert length(pages) == 13
    assert Enum.at(pages, 11) == Badge.Page.Store
    assert Enum.at(pages, 12) == Badge.App.Goatwars.Page
    assert apply(module, :for_key, [:square, 2]) == Badge.App.Goatwars.Page
    assert apply(module, :screens, []) == 3
    page = apply(module, :for_key, [:square, 2])
    state = page.init()
    assert state.match.replay == []
  end

  test "USB packs retain startup and assets without duplicate page modules", %{dir: dir} do
    inputs = fixtures(dir)
    paths = Usb.build!(inputs, Path.join(dir, "out"))
    inspected = Path.join(dir, "inspect.avm")
    # Normalize metadata flags for the legacy host archive inspector.
    original = File.read!(paths.firmware)
    assert :binary.match(original, "avm_badge/priv/application.bin") != :nomatch
    name = "avm_badge/priv/application.bin"
    File.write!(inspected, :binary.replace(original, <<2::32, 0::32, name::binary>>,
      <<0::32, 0::32, name::binary>>))
    firmware = :packbeam_api.list(to_charlist(inspected))
    names = Enum.map(firmware, & :packbeam_api.get_element_name/1)
    assert Enum.count(names, &(&1 == ~c"Elixir.Badge.Pages.beam")) == 1
    assert ~c"Elixir.UsbFixtureBoot.beam" in names
    assert Enum.any?(firmware, & :packbeam_api.is_entrypoint/1)
    assets = :packbeam_api.list(to_charlist(paths.assets))
    names = Enum.map(assets, & :packbeam_api.get_element_name/1)
    assert ~c"assets/priv/logo/test.rgba" in names
    assert ~c"Elixir.Badge.App.Goatwars.Page.beam" in names
    assert File.stat!(paths.firmware).size <= 671_744
    assert File.stat!(paths.assets).size <= 262_144
  end

  test "oversized assets fail before an installable output is produced", %{dir: dir} do
    inputs = fixtures(dir)
    File.write!(inputs.assets, File.read!(inputs.assets) <> :binary.copy(<<0>>, 262_144))
    output = Path.join(dir, "out")
    assert_raise Mix.Error, ~r/assets.*partition/, fn -> Usb.build!(inputs, output) end
    refute File.exists?(Path.join(output, "firmware.avm"))
    refute File.exists?(Path.join(output, "assets.avm"))
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
    :ok = ExAtomVM.PackBEAM.make_avm([{boot_path, :beam_start}, {pages_path, :beam},
      {metadata, [file: "avm_badge/priv/application.bin"]}], main)
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
