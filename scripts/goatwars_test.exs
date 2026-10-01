Code.require_file("goatwars_core.exs", __DIR__)
Code.require_file(Path.expand("../../avm_badge/lib/badge/page.ex", __DIR__))

Enum.each(~w(art render/interstitial render/explosion render/layout render page/state page), fn file ->
  Code.require_file(Path.expand("../apps/goatwars/lib/badge/app/goatwars/" <> file <> ".ex", __DIR__))
end)

Code.require_file(Path.expand("../test/support/badge/app/goatwars/setup_test/guest_pilot.ex", __DIR__))
ExUnit.start()

Path.wildcard(Path.expand("../test/badge/app/goatwars/**/*_test.exs", __DIR__))
|> Enum.each(&Code.require_file/1)
