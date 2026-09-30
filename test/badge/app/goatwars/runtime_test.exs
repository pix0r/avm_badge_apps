defmodule Badge.App.Goatwars.RuntimeTest do
  use ExUnit.Case

  @root Path.expand("../../../..", __DIR__)
  @supported @root
             |> Path.join("test/fixtures/atomvm_elixir_functions.txt")
             |> File.read!()
             |> String.split("\n", trim: true)
             |> MapSet.new()

  test "all compiled game files use supported Elixir library functions" do
    source =
      @root
      |> Path.join("apps/goatwars/lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.sort_by(fn path -> if Path.basename(path) == "controller.ex", do: 0, else: 1 end)
      |> Enum.map_join("\n", &File.read!/1)
      |> String.replace("Badge.App.Goatwars", "GoatwarsRuntimeAudit")

    binaries = Code.compile_string(source)
    modules = MapSet.new(Enum.map(binaries, &elem(&1, 0)))

    unsupported =
      Enum.flat_map(binaries, fn {_module, binary} ->
        {:ok, {_module, [{:imports, imports}]}} = :beam_lib.chunks(binary, [:imports])

        for {module, function, arity} <- imports,
            String.starts_with?(Atom.to_string(module), "Elixir."),
            not MapSet.member?(modules, module),
            call = "#{module}:#{function}/#{arity}",
            not MapSet.member?(@supported, call),
            do: call
      end)

    assert Enum.uniq(unsupported) == []
  end
end
