root = Path.expand("..", __DIR__)
files = ~w(config player arena state game input controller bot match)
Enum.each(files, &Code.require_file(Path.join([root, "apps/beamwars/lib", &1 <> ".ex"])))
