ExUnit.start()

Path.wildcard(Path.join(__DIR__, "support/**/*.ex")) |> Enum.each(&Code.require_file/1)
