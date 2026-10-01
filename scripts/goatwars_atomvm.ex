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
    {:ok, settings} = Page.handle_key({:char, ?f}, settings)
    {:ok, restarted} = Page.handle_key({:edit, :newline}, settings)
    false = restarted.started
    200 = restarted.match.game.config.step_ms
    restarted = restarted |> Page.advance(0) |> Page.advance(3000)
    1 = Page.advance(restarted, 3199).match.game.tick
    2 = Page.advance(restarted, 3200).match.game.tick

    controls =
      Enum.reduce([{:move, :left}, {:char, ?z}, {:char, ?1}, {:char, ?9}], Page.init(), fn event, page ->
        {:ok, next} = Page.handle_key(event, page)
        next
      end)

    %{1 => :human, 2 => :human, 3 => :human, 4 => :human} = controls.match.controllers
    %{1 => :left, 2 => :left, 3 => :left, 4 => :left} = controls.match.pending
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
