defmodule GoatwarsReadiness do
  alias Badge.App.Goatwars.{Page, Match}

  def start do
    rounds(1)
    state = Page.init()
    0 = state.match.game.tick
    state = Page.advance(state, -10_000)
    state = Page.advance(state, -7_000)
    true = state.started
    1 = state.match.game.tick
    [] = state.match.replay
    {:ok, paused} = Page.handle_key({:char, 32}, state)
    ^paused = Page.advance(paused, 100_000)
    {:ok, settings} = Page.handle_key({:char, ?s}, state)
    ^settings = Page.advance(settings, 100_000)
    {:ok, restarted} = Page.handle_key({:edit, :newline}, settings)
    false = restarted.started
    true = length(Page.render(restarted)) > 0
    :io.format(~c"GoatWars readiness passed~n")
    :ok
  end

  defp rounds(21), do: :ok

  defp rounds(seed) do
    match = Match.demo(%{width: 78, height: 46, explosion_radius: 2, retract_speed: 8}, seed)
    match = Match.run(match, 3000)
    true = match.game.status != :running
    true = length(match.replay) == match.game.tick
    :io.format(~c"Seed ~p: ~p ticks, ~p~n", [seed, match.game.tick, match.game.status])
    rounds(seed + 1)
  end
end
