defmodule Badge.App.Beamwars.Match do
  @moduledoc """
  Pure match runner. Tick once for interactive play or run without clocks for
  headless simulation. Controller entries are `:human` or `{module, memory}`.
  Replay commands are stored newest first, one entry per completed tick.
  """
  alias Badge.App.Beamwars.{Bot, Config, Game, Player, State}

  @enforce_keys [:game, :controllers]
  defstruct [
    :game,
    :controllers,
    scores: %{},
    totals: %{},
    bonus: 5000,
    awarded_bonus: nil,
    pending: %{},
    replay: [],
    events: []
  ]

  @type t :: %__MODULE__{
          game: State.t(),
          controllers: map(),
          pending: map(),
          replay: [Game.inputs()],
          events: [Game.event()]
        }

  @doc "Creates a deterministic four-bot match with edge-midpoint spawns."
  def demo(options \\ %{width: 64, height: 36}, seed \\ 1, profiles \\ %{}) do
    {:ok, config} = Config.new(options)
    w = config.width
    h = config.height

    roster = [
      %Player{id: 1, position: {div(w, 2), h - 1}, direction: :north},
      %Player{id: 2, position: {div(w, 2), 0}, direction: :south},
      %Player{id: 3, position: {0, div(h, 2)}, direction: :east},
      %Player{id: 4, position: {w - 1, div(h, 2)}, direction: :west}
    ]

    roster = Enum.reject(roster, &(Map.get(profiles, &1.id) == :inactive))
    {:ok, game} = Game.new(config, roster)

    controllers =
      roster
      |> Enum.map(
        &{&1.id, controller(Map.get(profiles, &1.id, :intermediate), seed * 31 + &1.id * 13)}
      )
      |> Map.new()

    %__MODULE__{game: game, controllers: controllers, bonus: config.bonus_start}
  end

  defp controller(:human, _seed), do: :human
  defp controller({module, memory}, _seed) when is_atom(module), do: {module, memory}
  defp controller(profile, seed), do: {Bot, Bot.init(seed, profile)}

  @doc "Switches ownership and discards any old owner's pending turn."
  def control(match, id, controller) do
    _player = Map.fetch!(match.game.players, id)

    %{
      match
      | controllers: Map.put(match.controllers, id, controller),
        pending: Map.delete(match.pending, id)
    }
  end

  @doc "Queues a human turn for the next tick; the last turn before the tick wins."
  def command(match, id, turn) when turn == :left or turn == :right do
    case {Map.get(match.controllers, id), Map.get(match.game.players, id)} do
      {:human, %Player{alive: true}} -> %{match | pending: Map.put(match.pending, id, turn)}
      _ -> match
    end
  end

  @spec tick(t()) :: t()
  def tick(%__MODULE__{game: %State{status: status}} = match) when status != :running, do: match

  def tick(match) do
    {turns, controllers} =
      Enum.reduce(Game.living(match.game), {%{}, match.controllers}, fn player, acc ->
        choose(match, player.id, acc)
      end)

    {:ok, game, events} = Game.step(match.game, turns)

    scores =
      Enum.reduce(Game.living(game), match.scores, fn player, scores ->
        Map.put(scores, player.id, Map.get(scores, player.id, 0) + game.config.points_per_tick)
      end)

    bonus = max(game.config.bonus_start - game.tick * game.config.bonus_decay, 0)

    awarded_bonus =
      case game.status do
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
        replay: [turns | match.replay]
    }
  end

  @spec run(t(), non_neg_integer()) :: t()
  def run(match, ticks) when ticks >= 0, do: run_ticks(match, ticks)
  defp run_ticks(match, 0), do: match

  defp run_ticks(%__MODULE__{game: %State{status: status}} = match, _) when status != :running,
    do: match

  defp run_ticks(match, ticks), do: run_ticks(tick(match), ticks - 1)

  defp choose(match, id, {turns, controllers}) do
    {turn, controller} =
      case Map.fetch!(controllers, id) do
        :human ->
          {Map.get(match.pending, id), :human}

        {module, memory} ->
          {turn, memory} = module.choose(match.game, id, memory)
          {turn, {module, memory}}
      end

    turns = if turn == nil, do: turns, else: Map.put(turns, id, turn)
    {turns, Map.put(controllers, id, controller)}
  end
end
