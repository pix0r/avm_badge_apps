defmodule Badge.App.Beamwars.CLITest do
  use ExUnit.Case, async: true

  test "headless runner accepts AI and blast settings and finishes contracting rounds" do
    script = Path.expand("../../scripts/beamwars_headless.exs", __DIR__)

    {output, status} =
      System.cmd(System.find_executable("elixir"), [
        script,
        "--rounds",
        "2",
        "--level",
        "expert",
        "--explosion-radius",
        "2",
        "--retract-speed",
        "4",
        "--shrink-after",
        "12",
        "--shrink-every",
        "6"
      ])

    assert status == 0, output
    assert output =~ "2 rounds completed"
    assert output =~ ~r/contractions=[1-9]/
  end
end
