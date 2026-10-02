defmodule GoatwarsReadiness do
  alias Badge.App.Goatwars.{Page, Match, Game}

  def start do
    for profiles <- [%{}, %{3 => :inactive, 4 => :inactive}] do
      page = Page.init(countdown_ms: 0, profiles: profiles) |> Page.advance(0)
      200 = Page.tick_interval(page)
      100 = Page.refresh(page)
      1 = Page.advance(page, 199).match.game.tick
      next = Page.advance(page, 200)
      2 = next.match.game.tick
      2 = Page.advance(next, 399).match.game.tick
      3 = Page.advance(next, 400).match.game.tick
    end
    rounds(1)
    state = Page.init()
    :loading = Map.fetch!(state, :screen)
    state = Page.advance(state, 0)
    :loading = Map.fetch!(state, :screen)
    true = length(Page.render(state)) > 0
    state = Page.advance(state, 100)
    :title = Map.fetch!(state, :screen)
    ^state = Page.advance(state, -100_000)
    true = length(Page.render(state)) > 0
    {:ok, state} = Page.handle_key(:enter, state)
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
    210 = restarted.match.game.config.step_ms
    restarted = restarted |> Page.advance(0) |> Page.advance(3000)
    210 = Page.tick_interval(restarted)
    1 = Page.advance(restarted, 3209).match.game.tick
    2 = Page.advance(restarted, 3210).match.game.tick

    controls =
      Enum.reduce([{:move, :left}, {:char, ?z}, {:char, ?1}, {:char, ?9}], Page.init(countdown_ms: 0), fn event, page ->
        :ignore = Page.handle_key(event, page)
        page
      end)

    controls = Page.advance(controls, 0)
    %{1 => :human, 2 => :human, 3 => :human, 4 => :human} = controls.match.controllers
    %{} = controls.match.pending
    :west = controls.match.game.players[1].direction
    wall_turn()
    true = length(Page.render(restarted)) > 0
    :io.format(~c"GoatWars readiness passed~n")
    :ok
  end

  defp wall_turn do
    page = Page.init(countdown_ms: 0)
    {:ok, game} = Game.new(page.match.game.config, [
      %{id: 1, position: {0, 10}, direction: :west},
      %{id: 2, position: {11, 10}, direction: :east}
    ])
    match = Match.new(Game.compact(game), %{1 => :human, 2 => :human})
    false = Match.tick(match).game.players[1].alive
    page = %{page | match: match}
    :ignore = Page.handle_key({:move, :left}, page)
    next = Page.advance(page, 0)
    true = next.match.game.players[1].alive
    {0, 11} = next.match.game.players[1].position
    :south = next.match.game.players[1].direction
    :south = Page.advance(next, 100).match.game.players[1].direction
    :ok = Page.leave(next)
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
