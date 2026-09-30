defmodule Badge.App.Goatwars.Setup do
  @moduledoc "Pure player settings; key presets remain unique by swapping assignments."
  alias __MODULE__.Slot
  @modes [:human, :beginner, :intermediate, :expert, :pro, :inactive]
  @keys [:arrows, :ad, :jl, :vn]

  def new(controllers \\ %{}) do
    slots =
      [{1, :arrows}, {2, :ad}, {3, :jl}, {4, :vn}]
      |> Enum.map(fn {id, keys} ->
        {id, Slot.new(id, keys, Map.get(controllers, id, :intermediate))}
      end)
      |> Map.new()

    %{slots: slots, retract: true}
  end

  def controllers(setup),
    do: Map.fetch!(setup, :slots) |> Enum.map(fn {id, slot} -> {id, Map.fetch!(slot, :mode)} end) |> Map.new()

  def valid?(setup),
    do: length(Enum.filter(Map.values(Map.fetch!(setup, :slots)), &(Map.fetch!(&1, :mode) != :inactive))) >= 2

  def mode(setup, id, mode),
    do: %{setup | slots: Map.put(Map.fetch!(setup, :slots), id, %{Map.fetch!(Map.fetch!(setup, :slots), id) | mode: mode})}

  def cycle_mode(setup, id, delta, modes \\ @modes),
    do: mode(setup, id, cycle(modes, Map.fetch!(Map.fetch!(setup, :slots)[id], :mode), delta))

  def cycle_keys(setup, id), do: keys(setup, id, cycle(@keys, Map.fetch!(Map.fetch!(setup, :slots)[id], :keys), 1))

  def keys(setup, id, preset) do
    previous = Map.fetch!(Map.fetch!(setup, :slots)[id], :keys)

    slots =
      Map.fetch!(setup, :slots)
      |> Enum.map(fn
        {^id, slot} -> {id, %{slot | keys: preset}}
        {other, %{keys: ^preset} = slot} -> {other, %{slot | keys: previous}}
        entry -> entry
      end)
      |> Map.new()

    %{setup | slots: slots}
  end

  def binding(setup, event) do
    Enum.reduce(Map.fetch!(setup, :slots), nil, fn {id, slot}, found ->
      turn = key_turn(Map.fetch!(slot, :keys), event)
      if turn != nil and Map.fetch!(slot, :mode) != :inactive, do: {id, turn}, else: found
    end)
  end

  def label(:human), do: "Human"
  def label(:beginner), do: "AI Novice"
  def label(:intermediate), do: "AI Intermediate"
  def label(:expert), do: "AI Expert"
  def label(:pro), do: "AI Pro"
  def label(:inactive), do: "Inactive"
  def label(_), do: "Custom AI"
  def key_label(:arrows), do: "L/R"
  def key_label(:ad), do: "A/D"
  def key_label(:jl), do: "J/L"
  def key_label(:vn), do: "V/N"

  defp cycle(choices, current, delta) do
    index = index(choices, current, 0)
    :lists.nth(rem(index + delta + length(choices), length(choices)) + 1, choices)
  end

  defp index([], _, _), do: 0
  defp index([current | _], current, index), do: index
  defp index([_ | rest], current, index), do: index(rest, current, index + 1)
  defp key_turn(:arrows, {:move, turn}) when turn == :left or turn == :right, do: turn
  defp key_turn(:ad, {:char, ?a}), do: :left
  defp key_turn(:ad, {:char, ?d}), do: :right
  defp key_turn(:jl, {:char, ?j}), do: :left
  defp key_turn(:jl, {:char, ?l}), do: :right
  defp key_turn(:vn, {:char, ?v}), do: :left
  defp key_turn(:vn, {:char, ?n}), do: :right
  defp key_turn(_, _), do: nil
end
