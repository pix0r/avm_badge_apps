defmodule AvmBadgeApps.Usb do
  @moduledoc "Builds an offline GoatWars USB image from existing firmware and assets packs."

  def pages_source(source, module \\ Badge.Pages) do
    ast = Code.string_to_quoted!(source)

    {ast, count} =
      Macro.prewalk(ast, 0, fn
        {:@, meta, [{:pages, attr_meta, [pages]}]}, count when is_list(pages) ->
          page = {:__aliases__, [], [:Badge, :App, :Goatwars, :Page]}
          {{:@, meta, [{:pages, attr_meta, [pages ++ [page]]}]}, count + 1}

        node, count ->
          {node, count}
      end)

    if count != 1, do: Mix.raise("expected one firmware pages list")
    {:defmodule, meta, [_name, body]} = ast
    {:defmodule, meta, [module, body]} |> Macro.to_string()
  end

  def build!(inputs, output) do
    if File.stat!(inputs.assets).size > 262_144,
      do: Mix.raise("assets and game exceed assets partition")

    if File.stat!(inputs.game).size > Badge.Store.max_pack(),
      do: Mix.raise("game exceeds Store pack limit")

    File.mkdir_p!(output)
    stage = Path.join(output, "stage")
    File.mkdir_p!(stage)
    original = :code.get_object_code(Badge.Pages)

    try do
      [{Badge.Pages, binary}] = Code.compile_string(pages_source(inputs.pages_source))
      pages = Path.join(stage, "Elixir.Badge.Pages.beam")
      File.write!(pages, binary)
      stripped = Path.join(stage, "base.avm")
      strip_pages!(inputs.firmware, stripped)
      main = Path.join(stage, "firmware.avm")
      assets = Path.join(stage, "assets.avm")
      :ok = ExAtomVM.PackBEAM.make_avm([{pages, :beam}, {stripped, :avm}], main)
      {extra, remaining} = split_game!(inputs.game, File.stat!(inputs.assets).size, stage)

      if extra do
        combined = Path.join(stage, "combined.avm")
        :ok = ExAtomVM.PackBEAM.make_avm([{main, :avm}, {extra, :avm}], combined)
        File.rename!(combined, main)
      end

      :ok = ExAtomVM.PackBEAM.make_avm([{inputs.assets, :avm}, {remaining, :avm}], assets)
      check!(main, 671_744, "firmware")
      check!(assets, 262_144, "assets")
      paths = %{firmware: Path.join(output, "firmware.avm"), assets: Path.join(output, "assets.avm")}
      File.cp!(main, paths.firmware)
      File.cp!(assets, paths.assets)
      paths
    after
      case original do
        {module, binary, file} -> :code.load_binary(module, file, binary)
        :error -> :ok
      end

      File.rm_rf!(stage)
    end
  end

  defp split_game!(game, assets_size, stage) do
    needed = assets_size + File.stat!(game).size - 40 - 262_144

    if needed <= 0 do
      {nil, game}
    else
      <<header::binary-size(24), bytes::binary>> = File.read!(game)
      {extra, remaining} = split_sections(bytes, needed, [])
      extra_path = Path.join(stage, "game-main.avm")
      remaining_path = Path.join(stage, "game-assets.avm")
      ending = <<0::32, 0::32, 0::32, "end", 0>>
      File.write!(extra_path, [header, :lists.reverse(extra), ending])
      File.write!(remaining_path, [header, remaining])
      {extra_path, remaining_path}
    end
  end

  defp split_sections(bytes, needed, extra) when needed <= 0, do: {extra, bytes}

  defp split_sections(<<size::32, _::binary>> = bytes, needed, extra)
       when size >= 16 and byte_size(bytes) >= size do
    <<section::binary-size(size), rest::binary>> = bytes
    split_sections(rest, needed - size, [section | extra])
  end

  defp split_sections(_, _, _), do: Mix.raise("assets and game exceed partition capacity")

  defp strip_pages!(input, output) do
    <<header::binary-size(24), sections::binary>> = File.read!(input)
    {kept, count} = sections(sections, [], 0)
    if count != 1, do: Mix.raise("expected one packed firmware pages module")
    File.write!(output, [header, kept])
  end

  defp sections(<<0::32, 0::32, 0::32, "end", 0>> = ending, acc, count),
    do: {Enum.reverse([ending | acc]), count}

  defp sections(<<size::32, _::binary>> = bytes, acc, count)
       when size >= 16 and byte_size(bytes) >= size do
    <<section::binary-size(size), rest::binary>> = bytes
    <<_::binary-size(12), named::binary>> = section
    name = hd(:binary.split(named, <<0>>))

    if name == "Elixir.Badge.Pages.beam",
      do: sections(rest, acc, count + 1),
      else: sections(rest, [section | acc], count)
  end

  defp sections(_, _, _), do: Mix.raise("invalid firmware pack sections")

  defp check!(path, limit, name) do
    if File.stat!(path).size > limit, do: Mix.raise("#{name} exceeds partition")
  end
end
