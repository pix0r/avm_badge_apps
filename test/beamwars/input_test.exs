defmodule Badge.App.Beamwars.InputTest do
  use ExUnit.Case, async: true
  alias Badge.App.Beamwars.Input

  test "a tap between ticks is consumed exactly once" do
    input = Input.new() |> Input.press(1, :left) |> Input.release(1, :left)
    assert {%{1 => :left}, input} = Input.take(input)
    assert {%{}, _} = Input.take(input)
  end

  test "held keys turn on every tick, without operating-system repeat" do
    input = Input.new() |> Input.press(1, :right)
    assert {%{1 => :right}, input} = Input.take(input)
    assert {%{1 => :right}, input} = Input.take(input)
    assert {%{}, _} = input |> Input.release(1, :right) |> Input.take()
  end

  test "repeat keydown events do not create extra pending taps" do
    input = Input.new() |> Input.press(1, :left)
    {_, input} = Input.take(input)
    input = input |> Input.press(1, :left) |> Input.release(1, :left)
    assert {%{}, _} = Input.take(input)
  end

  test "latest press wins within a tick; releasing it restores the other held key" do
    input = Input.new() |> Input.press(1, :left) |> Input.press(1, :right)
    assert {%{1 => :right}, input} = Input.take(input)
    assert {%{1 => :left}, _} = input |> Input.release(1, :right) |> Input.take()
  end

  test "four local controllers have independent input state" do
    input = Enum.reduce(1..4, Input.new(), &Input.press(&2, &1, :left))
    assert {%{1 => :left, 2 => :left, 3 => :left, 4 => :left}, _} = Input.take(input)
  end
end
