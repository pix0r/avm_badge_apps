defmodule GoatwarsReadiness do
  alias Badge.App.Goatwars.{Page, Match, Game}

  def start do
    runtime_lifecycle()
    failed_worker()
    timed_turn()
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
    for started <- [true, false] do
      input = %{Page.init(countdown_ms: 0) | started: started, launch_at: :erlang.monotonic_time(:millisecond) - 1}
      :ignore = Page.handle_key({:move, :left}, input)
      waiting = Page.tick(input)
      0 = waiting.match.game.tick
      stepped = receive do
        {:goatwars_step, _, _, _, _} = message ->
          {:ok, next} = Page.handle_info(message, waiting)
          next
      end
      1 = stepped.match.game.tick
      :west = stepped.match.game.players[1].direction
      :undefined = :erlang.get(input.input_ref)
      :ok = Page.leave(stepped)
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

  defp runtime_lifecycle do
    previous = :erlang.system_info(:schedulers_online)
    for action <- [{:char, 32}, {:char, ?s}, {:char, ?r}, :leave] do
      state = Page.init(countdown_ms: 0)
      waiting = Page.tick(state)
      ^previous = :erlang.system_info(:schedulers_online)
      stepped = receive do
        {:goatwars_step, _, _, _, _} = message ->
          {:ok, next} = Page.handle_info(message, waiting)
          next
      end
      ^previous = :erlang.system_info(:schedulers_online)
      if action == :leave, do: Page.leave(stepped), else: Page.handle_key(action, stepped)
      ^previous = :erlang.system_info(:schedulers_online)
    end
  end

  defp timed_turn do
    previous = :erlang.system_info(:schedulers_online)
    state = Page.tick(Page.init(countdown_ms: 0))
    next = receive do
      {:goatwars_step, _, _, _, _} = message ->
        {:ok, next} = Page.handle_info(message, state)
        next
    end
    true = length(Page.render(next)) > 0
    due = receive do
      {:goatwars_due, _, _, _} = message -> message
    end
    {:ok, final} = Page.handle_info(due, next)
    true = final.match == Match.tick(next.match)
    :undefined = :erlang.get({:goatwars_work, next.input_ref})
    2 = final.match.game.tick
    ^previous = :erlang.system_info(:schedulers_online)
    Page.leave(final)
    :ignore = Page.handle_info(due, final)
  end

  defp failed_worker do
    previous = :erlang.system_info(:schedulers_online)
    state = Page.init(countdown_ms: 0)
    match = Map.fetch!(state, :match)
    controllers = Map.put(Map.fetch!(match, :controllers), 2, {GoatwarsBrokenController, nil})
    waiting = Page.tick(%{state | match: %{match | controllers: controllers}})
    try do
      receive do
        {:DOWN, _, :process, _, _} = message ->
          try do
            Page.handle_info(message, waiting)
          catch
            :error, _ -> :ok
          end
      end
      ^previous = :erlang.system_info(:schedulers_online)
    after
      Page.leave(waiting)
    end
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

defmodule GoatwarsBrokenController do
  def choose(_game, _id, _memory), do: :erlang.error(:fixture_failure)
end
