defmodule Badge.App.Goatron.Match do
  @moduledoc """
  Pure match runner. Tick once for interactive play or run without clocks for
  headless simulation. Controller entries are `:human` or `{module, memory}`.
  Replay commands are stored newest first, one entry per completed tick.
  """
  alias Badge.App.Goatron.{Bot, Config, Game, Player, State}

  @enforce_keys [:game, :controllers]
  defstruct [:game, :controllers, pending: %{}, replay: [], events: []]
  @type t :: %__MODULE__{game: State.t(), controllers: map(), pending: map(), replay: [Game.inputs()], events: [Game.event()]}

  @doc "Creates a deterministic four-bot match with quarter-board spawns."
  def demo(options \\ %{width: 64, height: 36}, seed \\ 1) do
    {:ok, config} = Config.new(options)
    w = config.width
    h = config.height

    roster = [
      %Player{id: 1, position: {div(w, 4), div(h, 4)}, direction: :east},
      %Player{id: 2, position: {w - div(w, 4) - 1, div(h, 4)}, direction: :south},
      %Player{id: 3, position: {w - div(w, 4) - 1, h - div(h, 4) - 1}, direction: :west},
      %Player{id: 4, position: {div(w, 4), h - div(h, 4) - 1}, direction: :north}
    ]

    {:ok, game} = Game.new(config, roster)
    controllers = Map.new(roster, &{&1.id, {Bot, Bot.init(seed * 31 + &1.id * 13)}})
    %__MODULE__{game: game, controllers: controllers}
  end

  @doc "Switches ownership and discards any old owner's pending turn."
  def control(match, id, controller) do
    _player = Map.fetch!(match.game.players, id)
    %{match | controllers: Map.put(match.controllers, id, controller), pending: Map.delete(match.pending, id)}
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
    %{match | game: game, controllers: controllers, pending: %{}, events: events, replay: [turns | match.replay]}
  end

  @spec run(t(), non_neg_integer()) :: t()
  def run(match, ticks) when ticks >= 0, do: run_ticks(match, ticks)
  defp run_ticks(match, 0), do: match
  defp run_ticks(%__MODULE__{game: %State{status: status}} = match, _) when status != :running, do: match
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
