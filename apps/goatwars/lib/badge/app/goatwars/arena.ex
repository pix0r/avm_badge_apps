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
      right: config.width - 1,
      bottom: config.height - 1,
      next_shrink_tick: deadline(config.shrink_after)
    }
    |> stop_if_minimal()
  end

  @spec contains?(t(), {integer(), integer()}) :: boolean()
  def contains?(arena, {x, y}) do
    x >= arena.left and x <= arena.right and y >= arena.top and y <= arena.bottom
  end

  @spec advance(t(), Config.t(), non_neg_integer()) :: t()
  def advance(%{next_shrink_tick: nil} = arena, _config, _tick), do: arena

  def advance(%{next_shrink_tick: deadline} = arena, _config, tick)
      when tick < deadline,
      do: arena

  def advance(arena, config, tick) do
    %{
      arena
      | left: arena.left + 1,
        top: arena.top + 1,
        right: arena.right - 1,
        bottom: arena.bottom - 1,
        inset: arena.inset + 1,
        next_shrink_tick: arena.next_shrink_tick + config.shrink_every
    }
    |> stop_if_minimal()
    |> advance(config, tick)
  end

  def warning?(%{next_shrink_tick: nil}, _config, _tick), do: false

  def warning?(arena, config, tick),
    do: tick >= arena.next_shrink_tick - config.warning_ticks and tick < arena.next_shrink_tick

  defp deadline(:never), do: nil
  defp deadline(tick), do: tick

  defp stop_if_minimal(arena) when arena.right - arena.left < 2 or arena.bottom - arena.top < 2,
    do: %{arena | next_shrink_tick: nil}

  defp stop_if_minimal(arena), do: arena
end
