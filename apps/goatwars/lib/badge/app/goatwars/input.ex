defmodule Badge.App.Goatwars.Input do
  @moduledoc """
  Pure human input state, keyed by player ID rather than physical key bindings.

  A tap survives until the next `take/1`. Held buttons contribute on every tick.
  Repeated keydown notifications are ignored. The latest press wins if both turn
  buttons are pressed; releasing it restores the other held button.
  """

  def new, do: %{}

  def press(input, id, action) when action == :left or action == :right do
    player = Map.get(input, id, %{held: [], pending: nil})

    if :lists.member(action, Map.fetch!(player, :held)) do
      input
    else
      Map.put(input, id, %{held: [action | Map.fetch!(player, :held)], pending: action})
    end
  end

  def release(input, id, action) when action == :left or action == :right do
    case Map.get(input, id) do
      nil -> input
      player -> Map.put(input, id, %{player | held: Enum.filter(Map.fetch!(player, :held), &(&1 != action))})
    end
  end

  @doc "Returns this tick's turns and clears consumed taps, retaining held buttons."
  def take(input) do
    Enum.reduce(Map.to_list(input), {%{}, %{}}, fn {id, player}, {turns, next} ->
      action = Map.fetch!(player, :pending) || held_action(Map.fetch!(player, :held))
      turns = if action, do: Map.put(turns, id, action), else: turns
      next = if Map.fetch!(player, :held) == [], do: next, else: Map.put(next, id, %{player | pending: nil})
      {turns, next}
    end)
  end

  defp held_action([]), do: nil
  defp held_action([action | _]), do: action
end
