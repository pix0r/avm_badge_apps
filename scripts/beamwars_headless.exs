Code.require_file("beamwars_core.exs", __DIR__)
alias Badge.App.Beamwars.Match

{options, _, invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      rounds: :integer,
      width: :integer,
      height: :integer,
      seed: :integer,
      shrink_after: :integer,
      shrink_every: :integer,
      level: :string,
      explosion_radius: :integer,
      retract_speed: :integer
    ]
  )

if invalid != [], do: raise(ArgumentError, "unknown options: #{inspect(invalid)}")
rounds = Keyword.get(options, :rounds, 10)
if rounds < 1, do: raise(ArgumentError, "rounds must be positive")

rules = %{
  width: Keyword.get(options, :width, 78),
  height: Keyword.get(options, :height, 46),
  explosion_radius: Keyword.get(options, :explosion_radius, 2),
  retract_speed: Keyword.get(options, :retract_speed, 8)
}

rules =
  Enum.reduce([:shrink_after, :shrink_every], rules, fn key, config ->
    case Keyword.fetch(options, key) do
      {:ok, value} -> Map.put(config, key, value)
      :error -> config
    end
  end)

seed = Keyword.get(options, :seed, 1)

level =
  case Keyword.get(options, :level, "intermediate") do
    "beginner" -> :beginner
    "intermediate" -> :intermediate
    "expert" -> :expert
    "pro" -> :pro
    value -> raise(ArgumentError, "unknown AI level: #{value}")
  end

profiles = Map.new(1..4, &{&1, level})

{elapsed, results} =
  :timer.tc(fn ->
    for round <- 1..rounds do
      match = Match.demo(rules, seed + round - 1, profiles)
      result = Match.run(match, rules.width * rules.height * 5)

      if result.game.status == :running,
        do: raise("round did not terminate within the safety tick budget")

      IO.puts(
        "round=#{round} seed=#{seed + round - 1} ticks=#{result.game.tick} " <>
          "result=#{inspect(result.game.status)} contractions=#{result.game.arena.inset}"
      )

      result.game.status
    end
  end)

IO.puts("#{length(results)} rounds completed in #{Float.round(elapsed / 1_000_000, 3)}s")
