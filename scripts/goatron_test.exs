Code.require_file("goatron_core.exs", __DIR__)
ExUnit.start()

Path.wildcard(Path.expand("../test/goatron/*_test.exs", __DIR__))
|> Enum.each(&Code.require_file/1)
