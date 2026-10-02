[firmware, output] = System.argv()
root = Path.expand("..", __DIR__)
Code.require_file(Path.join(root, "lib/avm_badge_apps/usb.ex"))
File.mkdir_p!(output)
game = Path.join(output, "goatwars.avm")
ebin = Path.join(output, "goatwars-beams")
File.mkdir_p!(ebin)
sources = Path.wildcard(Path.join(root, "apps/goatwars/lib/**/*.ex"))
{:ok, modules, _warnings} = Kernel.ParallelCompiler.compile_to_path(sources, ebin)
beams = modules |> Enum.map(&Path.join(ebin, "#{&1}.beam")) |> Enum.sort()
:ok = ExAtomVM.PackBEAM.make_avm(Enum.map(beams, &{&1, :beam}), game)
inputs = %{
  firmware: Path.join(firmware, "avm_badge.avm"),
  assets: Path.join(firmware, "assets.avm"),
  game: game,
  pages_source: File.read!(Path.join(firmware, "lib/badge/pages.ex"))
}
paths = AvmBadgeApps.Usb.build!(inputs, output)
for {name, path} <- paths, do: IO.puts("#{name}: #{path} (#{File.stat!(path).size} bytes)")
