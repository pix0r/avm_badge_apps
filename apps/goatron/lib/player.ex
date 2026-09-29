defmodule Badge.App.Goatron.Player do
  @moduledoc "A bike's identity and physical state. Controller assignments are external."
  @enforce_keys [:id, :position, :direction]
  defstruct [:id, :position, :direction, alive: true]

  @type direction :: :north | :east | :south | :west
  @type position :: {integer(), integer()}
  @type turn :: :left | :right | nil
  @type t :: %__MODULE__{id: integer(), position: position(), direction: direction(), alive: boolean()}

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_players}
  def new(%{id: id, position: {x, y} = position, direction: direction})
      when is_integer(id) and is_integer(x) and is_integer(y) do
    case direction do
      dir when dir in [:north, :east, :south, :west] ->
        {:ok, %__MODULE__{id: id, position: position, direction: dir}}

      _ ->
        {:error, :invalid_players}
    end
  end

  def new(_), do: {:error, :invalid_players}

  @spec move(t(), turn()) :: t()
  def move(player, turn) do
    direction = turn(player.direction, turn)
    %{player | direction: direction, position: step(player.position, direction)}
  end

  def turn(direction, nil), do: direction
  def turn(:north, :left), do: :west
  def turn(:east, :left), do: :north
  def turn(:south, :left), do: :east
  def turn(:west, :left), do: :south
  def turn(:north, :right), do: :east
  def turn(:east, :right), do: :south
  def turn(:south, :right), do: :west
  def turn(:west, :right), do: :north

  def step({x, y}, :north), do: {x, y - 1}
  def step({x, y}, :east), do: {x + 1, y}
  def step({x, y}, :south), do: {x, y + 1}
  def step({x, y}, :west), do: {x - 1, y}
end
