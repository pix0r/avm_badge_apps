defmodule Badge.App.Goatwars.SetupTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Bot, Match, Setup}
  alias __MODULE__.GuestPilot

  test "default adjacent key pairs address each goat independently" do
    setup = Setup.new()

    for {event, expected} <- [
          {{:move, :left}, {1, :left}},
          {{:move, :right}, {1, :right}},
          {{:char, ?z}, {2, :left}},
          {{:char, ?x}, {2, :right}},
          {{:char, ?1}, {3, :left}},
          {{:char, ?2}, {3, :right}},
          {{:char, ?9}, {4, :left}},
          {{:char, ?0}, {4, :right}}
        ] do
      assert Setup.binding(setup, event) == expected
    end

    assert Setup.binding(Setup.mode(setup, 3, :inactive), {:char, ?1}) == nil
    for char <- [?a, ?d, ?j, ?l, ?v, ?n], do: assert(Setup.binding(setup, {:char, char}) == nil)
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
    setup = Setup.mode(setup, 1, :human) |> Setup.mode(4, :inactive) |> Setup.cycle_keys(1)
    assert setup.slots[1].mode == :human
    assert Setup.binding(setup, {:char, ?z}) == {1, :left}
    assert Setup.binding(setup, {:move, :left}) == {2, :left}
    assert Setup.controllers(setup)[4] == :inactive
    assert Setup.valid?(setup)
    setup = Setup.mode(setup, 2, :inactive) |> Setup.mode(3, :inactive)
    refute Setup.valid?(setup)
  end
end
