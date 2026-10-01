defmodule Badge.App.Goatwars.RuntimeTest do
  use ExUnit.Case

  @root Path.expand("../../../..", __DIR__)
  @supported @root
             |> Path.join("test/fixtures/atomvm_elixir_functions.txt")
             |> File.read!()
             |> String.split("\n", trim: true)
             |> MapSet.new()

  test "all compiled game files use supported Elixir library functions" do
    sources =
      @root
      |> Path.join("apps/goatwars/lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.sort_by(fn path -> if Path.basename(path) == "controller.ex", do: 0, else: 1 end)
      |> Enum.map(fn path ->
        source = File.read!(path) |> String.replace("Badge.App.Goatwars", "GoatwarsRuntimeAudit")
        ast = Code.string_to_quoted!(source, file: path)

        Macro.prewalk(ast, fn
          {:__DIR__, _, context} when is_atom(context) -> Path.dirname(path)
          node -> node
        end)
      end)

    binaries = Code.compile_quoted({:__block__, [], sources})
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
