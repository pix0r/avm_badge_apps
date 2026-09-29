defmodule Badge.App.Beamwars.Config do
  @moduledoc "Validated rules and tick-based timing for one round."
  @enforce_keys [:width, :height]
  defstruct [:width, :height, shrink_after: :perimeter, shrink_every: 20, warning_ticks: 8, step_ms: 100]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          shrink_after: non_neg_integer() | :never | :perimeter,
          shrink_every: pos_integer(),
          warning_ticks: non_neg_integer(),
          step_ms: pos_integer()
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_rules}
  def new(%__MODULE__{} = config), do: validate(config)

  def new(%{width: _, height: _} = options) do
    allowed = [:width, :height, :shrink_after, :shrink_every, :warning_ticks, :step_ms]

    if Enum.all?(Map.keys(options), &Enum.member?(allowed, &1)) do
      validate(%__MODULE__{
        width: options.width,
        height: options.height,
        shrink_after: Map.get(options, :shrink_after, :perimeter),
        shrink_every: Map.get(options, :shrink_every, 20),
        warning_ticks: Map.get(options, :warning_ticks, 8),
        step_ms: Map.get(options, :step_ms, 100)
      })
    else
      {:error, :invalid_rules}
    end
  end

  def new(_), do: {:error, :invalid_rules}

  @doc "Number of distinct cells on the initial outer ring."
  def perimeter(%__MODULE__{width: 1, height: height}), do: height
  def perimeter(%__MODULE__{width: width, height: 1}), do: width
  def perimeter(%__MODULE__{width: width, height: height}), do: 2 * (width + height) - 4

  defp validate(config) do
    if positive?(config.width) and positive?(config.height) and positive?(config.step_ms) and
         positive?(config.shrink_every) and nonnegative?(config.warning_ticks) and
         shrink_time?(config.shrink_after) do
      shrink_after = if config.shrink_after == :perimeter, do: perimeter(config), else: config.shrink_after
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
