[beams, source, build] = System.argv()
apps = Path.wildcard(Path.join(beams, "Elixir.Badge.App.Goatwars.*.beam"))
if apps == [], do: raise("no compiled GoatWars modules")
libs = Path.wildcard(Path.join(build, "libs/**/*.beam"))
if libs == [], do: raise("no compiled AtomVM libraries")

exports =
  Enum.reduce(apps ++ libs, MapSet.new(), fn path, acc ->
    {:ok, {module, [{:exports, functions}]}} =
      :beam_lib.chunks(String.to_charlist(path), [:exports])

    Enum.reduce(functions, acc, fn {function, arity}, acc ->
      MapSet.put(acc, {module, function, arity})
    end)
  end)

builtins =
  Enum.reduce(["bifs.gperf", "nifs.gperf"], exports, fn name, acc ->
    text = File.read!(Path.join([source, "src/libAtomVM", name]))

    Enum.reduce(Regex.scan(~r/^([^:\s]+):([^\s]+)\/(\d+),/m, text), acc, fn [
                                                                              _,
                                                                              module,
                                                                              function,
                                                                              arity
                                                                            ],
                                                                            acc ->
      MapSet.put(
        acc,
        {String.to_atom(module), String.to_atom(function), String.to_integer(arity)}
      )
    end)
  end)

imports =
  Enum.flat_map(apps, fn path ->
    {:ok, {module, [{:imports, imports}]}} =
      :beam_lib.chunks(String.to_charlist(path), [:imports])

    Enum.map(imports, &{module, &1})
  end)

missing = Enum.reject(imports, fn {_, call} -> MapSet.member?(builtins, call) end)

if missing != [],
  do: raise("unresolved AtomVM imports: #{inspect(Enum.uniq(missing), limit: :infinity)}")

opcodes = File.read!(Path.join(source, "src/libAtomVM/opcodes.def"))

supported =
  Regex.scan(~r/^X_OPCODE(?:_HANDLER)?\([^,]+,\s*\d+,\s*([^,]+),/m, opcodes)
  |> Enum.map(fn [_, name] -> name end)
  |> MapSet.new()

used =
  Enum.flat_map(apps, fn path ->
    {:beam_file, _, _, _, _, functions} = :beam_disasm.file(String.to_charlist(path))

    Enum.flat_map(functions, fn {:function, _, _, _, instructions} ->
      Enum.map(instructions, fn
        {:bif, _, _, args, _} ->
          "bif#{length(args)}"

        {:gc_bif, _, _, _, args, _} ->
          "gc_bif#{length(args)}"

        {:init, _} ->
          "kill"

        {:test, :is_ne, _, _} ->
          "is_not_equal"

        {:test, :is_ne_exact, _, _} ->
          "is_not_eq_exact"

        {:test, :is_eq, _, _} ->
          "is_equal"

        {:test, name, _, _} ->
          Atom.to_string(name)

        instruction when is_tuple(instruction) and elem(instruction, 0) == :test ->
          Atom.to_string(elem(instruction, 1))

        instruction when is_tuple(instruction) ->
          Atom.to_string(elem(instruction, 0))

        instruction when is_atom(instruction) ->
          Atom.to_string(instruction)
      end)
    end)
  end)
  |> MapSet.new()

missing = MapSet.difference(used, supported) |> MapSet.to_list()
if missing != [], do: raise("unresolved AtomVM instructions: #{inspect(missing)}")

IO.puts(
  "AtomVM audit: #{length(apps)} modules, #{MapSet.size(used)} instructions, all imports resolved"
)
