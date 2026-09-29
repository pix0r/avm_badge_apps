Code.require_file("goatron_core.exs", __DIR__)
Code.require_file(Path.expand("../../avm_badge/lib/badge/page.ex", __DIR__))
Code.require_file(Path.expand("../apps/goatron/lib/render.ex", __DIR__))
Code.require_file(Path.expand("../apps/goatron/lib/page.ex", __DIR__))
ExUnit.start()

Path.wildcard(Path.expand("../test/goatron/*_test.exs", __DIR__))
|> Enum.each(&Code.require_file/1)
