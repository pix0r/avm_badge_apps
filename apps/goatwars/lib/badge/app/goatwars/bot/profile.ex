defmodule Badge.App.Goatwars.Bot.Profile do
  @moduledoc "Tunable AI policy and reaction timing, measured in game ticks."

  @defaults %{
    search_limit: 160,
    reaction_ticks: 3,
    decision_delay: 1,
    aggression: 4,
    caution: 12,
    prediction_ticks: 6,
    safe_room: 24,
    space_weight: 1,
    runway_weight: 1,
    runway_limit: 8,
    tie_modulus: 11
  }

  @type t :: map()

  def new(profile) when is_map(profile), do: new(Map.to_list(profile))
  def new(level) when is_atom(level), do: new(preset(level))

  def new(options) when is_list(options) do
    defaults = @defaults

    settings =
      Enum.reduce(options, defaults, fn {key, value}, settings ->
        if not Map.has_key?(settings, key),
          do: raise(ArgumentError, "unknown AI parameter: #{inspect(key)}")

        minimum =
          if :lists.member(key, [:decision_delay, :aggression, :caution, :space_weight, :runway_weight]),
            do: 0,
            else: 1

        if not is_integer(value) or value < minimum,
          do: raise(ArgumentError, "invalid AI parameter: #{inspect(key)}")

        Map.put(settings, key, value)
      end)

    if settings.decision_delay >= settings.reaction_ticks,
      do: raise(ArgumentError, "decision_delay must be less than reaction_ticks")

    settings
  end

  defp preset(:beginner),
    do: [
      search_limit: 48,
      reaction_ticks: 5,
      decision_delay: 2,
      aggression: 1,
      prediction_ticks: 3
    ]

  defp preset(:intermediate), do: []

  defp preset(:expert),
    do: [
      search_limit: 320,
      reaction_ticks: 2,
      decision_delay: 1,
      aggression: 6,
      prediction_ticks: 8
    ]

  defp preset(:pro),
    do: [
      search_limit: 640,
      reaction_ticks: 1,
      decision_delay: 0,
      aggression: 8,
      prediction_ticks: 10
    ]

  defp preset(level), do: raise(ArgumentError, "unknown AI level: #{inspect(level)}")
end
