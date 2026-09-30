defmodule Badge.App.Goatwars.Config do
  @moduledoc "Validated rules and tick-based timing for one round."

  @type t :: %{
          width: pos_integer(),
          height: pos_integer(),
          shrink_after: non_neg_integer() | :never | :perimeter,
          shrink_every: pos_integer(),
          warning_ticks: non_neg_integer(),
          step_ms: pos_integer(),
          explosion_radius: non_neg_integer(),
          retract_speed: non_neg_integer(),
          points_per_tick: non_neg_integer(),
          bonus_start: non_neg_integer(),
          bonus_decay: non_neg_integer()
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_rules}
  def new(%{width: _, height: _} = options) do
    allowed = [
      :width,
      :height,
      :shrink_after,
      :shrink_every,
      :warning_ticks,
      :step_ms,
      :explosion_radius,
      :retract_speed,
      :points_per_tick,
      :bonus_start,
      :bonus_decay
    ]

    if Enum.all?(Map.keys(options), &Enum.member?(allowed, &1)) do
      validate(%{
        width: Map.fetch!(options, :width),
        height: Map.fetch!(options, :height),
        shrink_after: Map.get(options, :shrink_after, :perimeter),
        shrink_every: Map.get(options, :shrink_every, 20),
        warning_ticks: Map.get(options, :warning_ticks, 8),
        step_ms: Map.get(options, :step_ms, 100),
        explosion_radius: Map.get(options, :explosion_radius, 0),
        retract_speed: Map.get(options, :retract_speed, 0),
        points_per_tick: Map.get(options, :points_per_tick, 25),
        bonus_start: Map.get(options, :bonus_start, 5000),
        bonus_decay: Map.get(options, :bonus_decay, 15)
      })
    else
      {:error, :invalid_rules}
    end
  end

  def new(_), do: {:error, :invalid_rules}

  @doc "Number of distinct cells on the initial outer ring."
  def perimeter(%{width: 1, height: height}), do: height
  def perimeter(%{width: width, height: 1}), do: width
  def perimeter(%{width: width, height: height}), do: 2 * (width + height) - 4

  defp validate(config) do
    if positive?(Map.fetch!(config, :width)) and positive?(Map.fetch!(config, :height)) and positive?(Map.fetch!(config, :step_ms)) and
         positive?(Map.fetch!(config, :shrink_every)) and nonnegative?(Map.fetch!(config, :warning_ticks)) and
         nonnegative?(Map.fetch!(config, :explosion_radius)) and nonnegative?(Map.fetch!(config, :retract_speed)) and
         nonnegative?(Map.fetch!(config, :points_per_tick)) and
         nonnegative?(Map.fetch!(config, :bonus_start)) and nonnegative?(Map.fetch!(config, :bonus_decay)) and
         shrink_time?(Map.fetch!(config, :shrink_after)) do
      shrink_after =
        if Map.fetch!(config, :shrink_after) == :perimeter, do: perimeter(config), else: Map.fetch!(config, :shrink_after)

      {:ok, %{config | shrink_after: shrink_after}}
    else
      {:error, :invalid_rules}
    end
  end

  defp shrink_time?(value) when value == :perimeter or value == :never, do: true
  defp shrink_time?(value), do: nonnegative?(value)
  defp positive?(value), do: is_integer(value) and value > 0
  defp nonnegative?(value), do: is_integer(value) and value >= 0
end
