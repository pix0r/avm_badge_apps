defmodule Badge.App.Beamwars.RuntimeTest do
  use ExUnit.Case

  test "compiled game avoids Map helpers absent from the badge-v1 library" do
    root = Path.expand("../../apps/beamwars/lib", __DIR__)
    files = ~w(config player arena state game input controller bot match setup render page)
    source = Enum.map_join(files, "\n", &File.read!(Path.join(root, &1 <> ".ex")))
    source = String.replace(source, "Badge.App.Beamwars", "BeamwarsRuntimeAudit")
    binaries = Code.compile_string(source)
    absent = [{Map, :new, 2}, {Map, :update, 4}, {Map, :update!, 3}]

    calls =
      Enum.flat_map(binaries, fn {_module, binary} ->
        {:ok, {_module, [{:imports, imports}]}} = :beam_lib.chunks(binary, [:imports])
        Enum.filter(imports, &(&1 in absent))
      end)

    assert Enum.uniq(calls) == []
  end
end
