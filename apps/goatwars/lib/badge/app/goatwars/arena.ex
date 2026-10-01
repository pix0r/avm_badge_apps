defmodule Badge.App.Goatwars.Arena do
  @moduledoc "Inclusive playable bounds and the next contraction deadline."
  alias Badge.App.Goatwars.Config

  @type t :: %{
          left: non_neg_integer(),
          top: non_neg_integer(),
          right: non_neg_integer(),
          bottom: non_neg_integer(),
          next_shrink_tick: non_neg_integer() | nil,
          inset: non_neg_integer()
        }

  def new(%{width: _, height: _} = config) do
    %{
      inset: 0,
      left: 0,
      top: 0,
      right: Map.fetch!(config, :width) - 1,
      bottom: Map.fetch!(config, :height) - 1,
      next_shrink_tick: deadline(Map.fetch!(config, :shrink_after))
    }
    |> stop_if_minimal()
  end

  @spec contains?(t(), {integer(), integer()}) :: boolean()
  def contains?(%{left: left, right: right, top: top, bottom: bottom}, {x, y}),
    do: x >= left and x <= right and y >= top and y <= bottom

  @spec advance(t(), Config.t(), non_neg_integer()) :: t()
  def advance(%{next_shrink_tick: nil} = arena, _config, _tick), do: arena

  def advance(%{next_shrink_tick: deadline} = arena, _config, tick)
      when tick < deadline,
      do: arena

  def advance(arena, config, tick) do
    %{
      arena
      | left: Map.fetch!(arena, :left) + 1,
        top: Map.fetch!(arena, :top) + 1,
        right: Map.fetch!(arena, :right) - 1,
        bottom: Map.fetch!(arena, :bottom) - 1,
        inset: Map.fetch!(arena, :inset) + 1,
        next_shrink_tick: Map.fetch!(arena, :next_shrink_tick) + Map.fetch!(config, :shrink_every)
    }
    |> stop_if_minimal()
    |> advance(config, tick)
  end

  def warning?(%{next_shrink_tick: nil}, _config, _tick), do: false

  def warning?(%{next_shrink_tick: deadline}, %{warning_ticks: warning}, tick),
    do: tick >= deadline - warning and tick < deadline

  defp deadline(:never), do: nil
  defp deadline(tick), do: tick

  defp stop_if_minimal(arena) when arena.right - arena.left < 2 or arena.bottom - arena.top < 2,
    do: %{arena | next_shrink_tick: nil}

  defp stop_if_minimal(arena), do: arena
end
