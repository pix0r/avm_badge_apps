[firmware, output] = System.argv()
File.mkdir_p!(output)
game = Path.join(output, "goatwars.avm")
beams = AvmBadgeApps.Pack.beams!(Mix.Project.compile_path(), "goatwars")
:ok = ExAtomVM.PackBEAM.make_avm(Enum.map(beams, &{&1, :beam}), game)
inputs = %{
  firmware: Path.join(firmware, "avm_badge.avm"),
  assets: Path.join(firmware, "assets.avm"),
  game: game,
  pages_source: File.read!(Path.join(firmware, "lib/badge/pages.ex"))
}
paths = AvmBadgeApps.Usb.build!(inputs, output)
for {name, path} <- paths, do: IO.puts("#{name}: #{path} (#{File.stat!(path).size} bytes)")
