[out, firmware, source, build, boot] = System.argv()
Code.require_file(Path.join(firmware, "deps/exatomvm/lib/packbeam.ex"))
beams = Path.wildcard(Path.join(out, "beams/*.beam"))
Code.require_file(Path.expand("../lib/avm_badge_apps/pack.ex", __DIR__))

apps =
  Enum.filter(beams, &(Path.basename(&1) |> String.starts_with?("Elixir.Badge.App.Goatwars.")))

expected = Path.wildcard(Path.expand("../apps/goatwars/lib/**/*.ex", __DIR__))
if length(apps) != length(expected), do: raise("expected all #{length(expected)} game modules")
apps = AvmBadgeApps.Pack.beams!(Path.join(out, "beams"), "goatwars")
pack = Path.join(out, "goatwars.avm")
:ok = ExAtomVM.PackBEAM.make_avm(Enum.map(apps, &{&1, :beam}), pack)
size = File.stat!(pack).size
if size > 65_536, do: raise("game pack exceeds Store limit: #{size}")
IO.puts("GoatWars pack: #{size} bytes")

calls =
  Enum.flat_map(apps, fn path ->
    {:ok, {_, [{:imports, imports}]}} = :beam_lib.chunks(String.to_charlist(path), [:imports])
    imports
  end)
  |> Enum.uniq()

File.write!(Path.join(out, "imports.term"), :erlang.term_to_binary(calls))

for entry <- ["GoatwarsReadiness", "GoatwarsResources"] do
  start = Path.join(out, "beams/Elixir.#{entry}.beam")
  others = Enum.reject(beams, &(&1 == start))
  inputs = [{start, :beam_start}] ++ Enum.map(others, &{&1, :beam}) ++ [{boot, :avm}]
  :ok = ExAtomVM.PackBEAM.make_avm(inputs, Path.join(out, "#{entry}.avm"))
end

System.argv([Path.join(out, "beams"), source, build])
Code.require_file(Path.join(__DIR__, "goatwars_audit.exs"))
