defmodule Badge.App.Goatwars.Match do
  @moduledoc """
  Pure match runner. Tick once for interactive play or run without clocks for
  headless simulation. Controller entries are `:human` or `{module, memory}`.
  Replay commands are stored newest first, one entry per completed tick.
  """
  @compile :no_line_info
  alias Badge.App.Goatwars.{Bot, Config, Game, SimpleBot, State}

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
    {:ok, %{width: w, height: h} = config} = Config.new(rules)
    {top_x, right_y} = if w == h, do: {div(w - 1, 2), div(h - 1, 2)}, else: {div(w, 2), div(h, 2)}

    roster = [
      %{id: 1, position: {div(w, 2), h - 1}, direction: :north},
      %{id: 2, position: {top_x, 0}, direction: :south},
      %{id: 3, position: {0, div(h, 2)}, direction: :east},
      %{id: 4, position: {w - 1, right_y}, direction: :west}
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

  @doc "Prepares AI commands for the current game before human commands close."
  def prepare(%{game: %{status: status}, controllers: controllers}) when status != :running,
    do: {%{}, controllers}

  def prepare(%{game: game, pending: pending, controllers: controllers}),
    do: choose_all(Game.living(game), game, pending, controllers, %{}, nil)

  @spec tick(t()) :: t()
  def tick(match), do: tick(match, nil)

  @doc "Steps the same game with prepared AI choices and the latest human commands."
  def tick(%{game: %{status: status}} = match, _choices) when status != :running, do: match

  def tick(%{game: game, controllers: controllers, pending: pending, scores: scores, replay: replay, record_replay: record} = match, choices) do
    {turns, controllers} =
      case choices do
        nil -> prepare(match)
        {turns, computed} -> latest_choices(Game.living(game), pending, computed, turns, controllers)
      end
    {:ok, game, events} = Game.step(game, turns)
    %{players: players, config: %{points_per_tick: points, bonus_start: start, bonus_decay: decay}, tick: tick, status: status} = game
    scores = score_players(:maps.to_list(players), scores, points)
    bonus = max(start - tick * decay, 0)

    awarded_bonus =
      case status do
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
        replay: if(record, do: [turns | replay], else: [])
    }
  end

  defp latest_choices([], _pending, _computed, turns, controllers), do: {turns, controllers}

  defp latest_choices([%{id: id} | rest], pending, computed, turns, controllers) do
    {turns, controllers} =
      case Map.fetch!(controllers, id) do
        :human ->
          turn = Map.get(pending, id)
          {if(turn == nil, do: Map.delete(turns, id), else: Map.put(turns, id, turn)), controllers}
        _bot -> {turns, Map.put(controllers, id, Map.fetch!(computed, id))}
      end
    latest_choices(rest, pending, computed, turns, controllers)
  end

  defp choose_all([], _game, _pending, controllers, turns, _prepared), do: {turns, controllers}

  defp choose_all([%{id: id} | rest], game, pending, controllers, turns, prepared) do
    {turn, controllers, prepared} =
      case Map.fetch!(controllers, id) do
        :human ->
          {Map.get(pending, id), controllers, prepared}

        {module, memory} ->
          prepared = if module == SimpleBot and prepared == nil, do: SimpleBot.prepare(game), else: prepared

          {turn, next_memory} =
            if module == SimpleBot, do: SimpleBot.choose_prepared(prepared, id, memory), else: module.choose(game, id, memory)

          controllers = if next_memory === memory, do: controllers, else: Map.put(controllers, id, {module, next_memory})
          {turn, controllers, prepared}
      end

    turns = if turn == nil, do: turns, else: Map.put(turns, id, turn)
    choose_all(rest, game, pending, controllers, turns, prepared)
  end

  defp score_players([], scores, _points), do: scores

  defp score_players([{id, %{alive: true}} | rest], scores, points),
    do: score_players(rest, Map.put(scores, id, Map.get(scores, id, 0) + points), points)

  defp score_players([_ | rest], scores, points), do: score_players(rest, scores, points)

  @spec run(t(), non_neg_integer()) :: t()
  def run(match, ticks) when is_integer(ticks) and ticks >= 0, do: run_ticks(match, ticks)
  defp run_ticks(match, 0), do: match

  defp run_ticks(%{game: %{status: status}} = match, _) when status != :running,
    do: match

  defp run_ticks(match, ticks), do: run_ticks(tick(match), ticks - 1)
end
