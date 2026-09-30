defmodule Badge.App.Goatwars.Match do
  @moduledoc """
  Pure match runner. Tick once for interactive play or run without clocks for
  headless simulation. Controller entries are `:human` or `{module, memory}`.
  Replay commands are stored newest first, one entry per completed tick.
  """
  alias Badge.App.Goatwars.{Bot, Config, Game, State}

  @type t :: %{
          game: State.t(),
          controllers: map(),
          pending: map(),
          replay: [Game.inputs()],
          events: [Game.event()]
        }

  @doc "Creates a match; set `record_replay: false` when commands need no history."
  def new(game, controllers, options \\ []) do
    %{
      game: game,
      controllers: controllers,
      scores: %{},
      totals: %{},
      bonus: Map.fetch!(Map.fetch!(game, :config), :bonus_start),
      awarded_bonus: nil,
      pending: %{},
      replay: [],
      events: [],
      record_replay: Keyword.get(options, :record_replay, true)
    }
  end

  @doc "Creates a deterministic four-bot match with edge-midpoint spawns."
  def demo(rules \\ %{width: 64, height: 36}, seed \\ 1, profiles \\ %{}, options \\ []) do
    {:ok, config} = Config.new(rules)
    w = Map.fetch!(config, :width)
    h = Map.fetch!(config, :height)

    roster = [
      %{id: 1, position: {div(w, 2), h - 1}, direction: :north},
      %{id: 2, position: {div(w, 2), 0}, direction: :south},
      %{id: 3, position: {0, div(h, 2)}, direction: :east},
      %{id: 4, position: {w - 1, div(h, 2)}, direction: :west}
    ]

    roster = Enum.reject(roster, &(Map.get(profiles, Map.fetch!(&1, :id)) == :inactive))
    {:ok, game} = Game.new(config, roster)

    controllers =
      roster
      |> Enum.map(
        &{Map.fetch!(&1, :id), controller(Map.get(profiles, Map.fetch!(&1, :id), :intermediate), seed * 31 + Map.fetch!(&1, :id) * 13)}
      )
      |> Map.new()

    new(game, controllers, options)
  end

  defp controller(:human, _seed), do: :human
  defp controller({module, memory}, _seed) when is_atom(module), do: {module, memory}
  defp controller(profile, seed), do: {Bot, Bot.init(seed, profile)}

  @doc "Switches ownership and discards any old owner's pending turn."
  def control(match, id, controller) do
    _player = Map.fetch!(Map.fetch!(Map.fetch!(match, :game), :players), id)

    %{
      match
      | controllers: Map.put(Map.fetch!(match, :controllers), id, controller),
        pending: Map.delete(Map.fetch!(match, :pending), id)
    }
  end

  @doc "Queues a human turn for the next tick; the last turn before the tick wins."
  def command(match, id, turn) when turn == :left or turn == :right do
    case {Map.get(Map.fetch!(match, :controllers), id), Map.get(Map.fetch!(Map.fetch!(match, :game), :players), id)} do
      {:human, %{alive: true}} -> %{match | pending: Map.put(Map.fetch!(match, :pending), id, turn)}
      _ -> match
    end
  end

  @spec tick(t()) :: t()
  def tick(%{game: %{status: status}} = match) when status != :running, do: match

  def tick(match) do
    {turns, controllers} =
      Enum.reduce(Game.living(Map.fetch!(match, :game)), {%{}, Map.fetch!(match, :controllers)}, fn player, acc ->
        choose(match, Map.fetch!(player, :id), acc)
      end)

    {:ok, game, events} = Game.step(Map.fetch!(match, :game), turns)

    scores =
      Enum.reduce(Game.living(game), Map.fetch!(match, :scores), fn player, scores ->
        Map.put(
          scores,
          Map.fetch!(player, :id),
          Map.get(scores, Map.fetch!(player, :id), 0) + Map.fetch!(Map.fetch!(game, :config), :points_per_tick)
        )
      end)

    bonus =
      max(
        Map.fetch!(Map.fetch!(game, :config), :bonus_start) - Map.fetch!(game, :tick) * Map.fetch!(Map.fetch!(game, :config), :bonus_decay),
        0
      )

    awarded_bonus =
      case Map.fetch!(game, :status) do
        {:winner, id} -> {id, bonus}
        _ -> nil
      end

    totals =
      case awarded_bonus do
        {id, amount} -> Map.put(scores, id, Map.get(scores, id, 0) + amount)
        nil -> scores
      end

    %{
      match
      | totals: totals,
        bonus: bonus,
        awarded_bonus: awarded_bonus,
        scores: scores,
        game: game,
        controllers: controllers,
        pending: %{},
        events: events,
        replay: if(Map.fetch!(match, :record_replay), do: [turns | Map.fetch!(match, :replay)], else: [])
    }
  end

  @spec run(t(), non_neg_integer()) :: t()
  def run(match, ticks) when is_integer(ticks) and ticks >= 0, do: run_ticks(match, ticks)
  defp run_ticks(match, 0), do: match

  defp run_ticks(%{game: %{status: status}} = match, _) when status != :running,
    do: match

  defp run_ticks(match, ticks), do: run_ticks(tick(match), ticks - 1)

  defp choose(match, id, {turns, controllers}) do
    {turn, controller} =
      case Map.fetch!(controllers, id) do
        :human ->
          {Map.get(Map.fetch!(match, :pending), id), :human}

        {module, memory} ->
          {turn, memory} = module.choose(Map.fetch!(match, :game), id, memory)
          {turn, {module, memory}}
      end

    turns = if turn == nil, do: turns, else: Map.put(turns, id, turn)
    {turns, Map.put(controllers, id, controller)}
  end
end
