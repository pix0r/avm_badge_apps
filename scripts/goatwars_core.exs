root = Path.expand("../apps/goatwars/lib/badge/app/goatwars", __DIR__)
files = ~w(config player arena state game input controller bot/profile bot match setup/slot setup)
Enum.each(files, &Code.require_file(Path.join(root, &1 <> ".ex")))
