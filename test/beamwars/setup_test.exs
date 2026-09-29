defmodule Badge.App.Beamwars.SetupTest do
  use ExUnit.Case, async: true
  alias Badge.App.Beamwars.{Bot, Match, Setup}

  defmodule GuestPilot do
    @behaviour Badge.App.Beamwars.Controller
    def init(seed), do: seed
    def choose(_public_game, _id, memory), do: {:left, memory + 1}
  end

  test "guest controller modules compete without a dependency on built-in AI" do
    match =
      Match.demo(%{width: 32, height: 24}, 1, %{
        1 => {GuestPilot, GuestPilot.init(7)},
        2 => :human,
        4 => :inactive
      })

    assert Map.keys(match.game.players) == [1, 2, 3]
    assert match.controllers[2] == :human
    next = Match.tick(match)
    assert next.controllers[1] == {GuestPilot, 8}
    assert next.replay |> hd() |> Map.fetch!(1) == :left
    assert match.controllers[3] |> elem(0) == Bot
  end

  test "setup cycles player modes and key presets independently" do
    setup = Setup.new()
    setup = Setup.mode(setup, 1, :human) |> Setup.mode(4, :inactive) |> Setup.keys(1, :ad)
    assert setup.slots[1].mode == :human
    assert Setup.binding(setup, {:char, ?a}) == {1, :left}
    assert Setup.binding(setup, {:move, :left}) == {2, :left}
    assert Setup.controllers(setup)[4] == :inactive
    assert Setup.valid?(setup)
    setup = Setup.mode(setup, 2, :inactive) |> Setup.mode(3, :inactive)
    refute Setup.valid?(setup)
  end
end
