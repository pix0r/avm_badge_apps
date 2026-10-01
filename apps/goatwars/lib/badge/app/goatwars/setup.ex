defmodule Badge.App.Goatwars.Setup do
  @moduledoc "Pure player settings; key presets remain unique by swapping assignments."
  alias __MODULE__.Slot
  @modes [:human, :beginner, :intermediate, :expert, :pro, :inactive]
  @keys [:arrows, :zx, :one_two, :nine_zero]
  @boards [{14, 24, "S"}, {23, 39, "M"}, {30, 51, "L"}, {46, 78, "XL"}]

  def new(controllers \\ %{}) do
    slots =
      [{1, :arrows}, {2, :zx}, {3, :one_two}, {4, :nine_zero}]
      |> Enum.map(fn {id, keys} ->
        {id, Slot.new(id, keys, Map.get(controllers, id, :intermediate))}
      end)
      |> Map.new()

    %{slots: slots, retract: true, board: {23, 23}, step_ms: 100}
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

  def cycle_board(%{board: {width, height}} = setup) do
    {edge, wide, _label} = cycle(@boards, :lists.keyfind(height, 1, @boards), 1)
    %{setup | board: {if(width == height, do: edge, else: wide), edge}}
  end

  def toggle_aspect(%{board: {width, height}} = setup) do
    board =
      if width == height do
        case :lists.keyfind(height, 1, @boards) do
          {_, wide, _} -> {wide, height}
          false -> {div(height * 39, 23), height}
        end
      else
        {height, height}
      end

    %{setup | board: board}
  end

  def adjust_speed(setup, delta), do: %{setup | step_ms: min(max(Map.fetch!(setup, :step_ms) + delta, 50), 400)}

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
  def key_label(:zx), do: "Z/X"
  def key_label(:one_two), do: "1/2"
  def key_label(:nine_zero), do: "9/0"

  def board_label({width, height}) do
    case :lists.keyfind(height, 1, @boards) do
      {_, wide, label} when width == height or width == wide -> label
      _ -> "Custom"
    end
  end

  defp cycle(choices, current, delta) do
    index = index(choices, current, 0)
    :lists.nth(rem(index + delta + length(choices), length(choices)) + 1, choices)
  end

  defp index([], _, _), do: 0
  defp index([current | _], current, index), do: index
  defp index([_ | rest], current, index), do: index(rest, current, index + 1)
  defp key_turn(:arrows, {:move, turn}) when turn == :left or turn == :right, do: turn
  defp key_turn(:zx, {:char, ?z}), do: :left
  defp key_turn(:zx, {:char, ?x}), do: :right
  defp key_turn(:one_two, {:char, ?1}), do: :left
  defp key_turn(:one_two, {:char, ?2}), do: :right
  defp key_turn(:nine_zero, {:char, ?9}), do: :left
  defp key_turn(:nine_zero, {:char, ?0}), do: :right
  defp key_turn(_, _), do: nil
end
