defmodule GoatwarsBenchmark do
  alias Badge.App.Goatwars.{Game, Page, Player}
  @rules %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8}
  @fixed System.get_env("GOATWARS_FIXED_WORKLOAD") == "1"

  def start do
    :io.format(~c"GW_BENCH word_bytes=~p~n", [:erlang.system_info(:wordsize)])
    started = :erlang.monotonic_time(:microsecond)
    repeat(fn -> Page.init(countdown_ms: 0, rules: @rules) end, 50)
    :io.format(~c"GW_INIT cpu_us=~p~n", [div(:erlang.monotonic_time(:microsecond) - started, 50)])

    if @fixed do
      for {width, height} <- [{23, 23}, {78, 46}], blocked <- [false, true] do
        state = fixed_state(width, height, blocked)
        started = :erlang.monotonic_time(:microsecond)
        repeat(fn -> Page.render(Page.advance(state, 0)) end, 1000)
        elapsed = :erlang.monotonic_time(:microsecond) - started

        :io.format(~c"GW_FIXED case=v1_~s_~px~p cpu_us=~p frames=1000~n", [
          if(blocked, do: ~c"blocked", else: ~c"cruise"),
          width,
          height,
          elapsed
        ])
      end
    end

    initial = Page.init(countdown_ms: 0, rules: @rules)
    terminal = play(initial, 0)

    for tick <- [0, 30, 31, 32, 33, 34, 35, 36, 64, 96, 97, 128, 192, terminal] do
      state = build(initial, 0, min(tick, terminal))
      now = tick * 100
      measure(~c"tick", state, fn -> Page.advance(state, now) end)
      measure(~c"render", state, fn -> Page.render(state) end)
      measure(~c"frame", state, fn -> Page.render(Page.advance(state, now)) end)
      :io.format(~c"GW_STATE tick=~p words=~p items=~p~n", [tick, :erts_debug.flat_size(state), length(Page.render(state))])
    end

    state = build(Page.init(countdown_ms: 0, rules: @rules), 0, 192)
    match = Map.fetch!(state, :match)
    state = %{state | match: %{match | game: %{Map.fetch!(match, :game) | tick: 240}}}
    measure(~c"render", state, fn -> Page.render(state) end)
    :io.format(~c"GW_STATE tick=240 words=~p items=~p~n", [:erts_debug.flat_size(state), length(Page.render(state))])

    started = :erlang.monotonic_time(:microsecond)
    ticks = rounds(5, 0, initial)
    elapsed = :erlang.monotonic_time(:microsecond) - started
    :io.format(~c"GW_ROUND cpu_us=~p ticks=~p rounds=5~n", [elapsed, ticks])

    for {width, height} <- [{14, 14}, {23, 23}, {30, 30}, {46, 46}, {24, 14}, {39, 23}, {51, 30}, {78, 46}] do
      rules = %{@rules | width: width, height: height}
      state = build(Page.init(countdown_ms: 0, rules: rules), 0, 4)
      started = :erlang.monotonic_time(:microsecond)
      repeat(fn -> Page.render(Page.advance(state, 400)) end, 1000)
      elapsed = :erlang.monotonic_time(:microsecond) - started

      :io.format(~c"GW_SIZE width=~p height=~p tick=4 alive=4 frame_cpu_us=~p bytes=~p~n", [
        width,
        height,
        div(elapsed, 1000),
        width * height * 4
      ])
    end

    :ok
  end

  def fixed_state(width, height, blocked) do
    state = Page.init(countdown_ms: 0, rules: %{@rules | width: width, height: height})
    left = div(width, 4)
    right = width - left - 1
    top = div(height, 4)
    bottom = height - top - 1

    players = [
      %{id: 1, position: {left, top}, direction: :east},
      %{id: 2, position: {right, top}, direction: :west},
      %{id: 3, position: {left, bottom}, direction: :north},
      %{id: 4, position: {right, bottom}, direction: :south}
    ]

    match = Map.fetch!(state, :match)
    {:ok, game} = Game.new(Map.fetch!(Map.fetch!(match, :game), :config), players)

    occupied =
      if blocked,
        do:
          Enum.reduce(players, Map.fetch!(game, :occupied), fn %{id: id, position: origin, direction: heading}, board ->
            Map.put(board, Player.step(origin, heading), id)
          end),
        else: Map.fetch!(game, :occupied)

    %{state | match: %{match | game: Game.compact(%{game | occupied: occupied})}}
  end

  defp build(state, _, 0), do: state
  defp build(state, now, n), do: build(Page.advance(state, now), now + 100, n - 1)

  defp measure(label, state, fun) do
    started = :erlang.monotonic_time(:microsecond)
    repeat(fun, 50)
    elapsed = :erlang.monotonic_time(:microsecond) - started

    :io.format(~c"GW_CPU tick=~p phase=~s cpu_us=~p~n", [
      Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :tick),
      label,
      div(elapsed, 50)
    ])
  end

  defp repeat(_, 0), do: :ok

  defp repeat(fun, n) do
    _ = fun.()
    repeat(fun, n - 1)
  end

  defp rounds(0, ticks, _initial), do: ticks
  defp rounds(n, ticks, initial), do: rounds(n - 1, ticks + play(initial, 0), initial)

  defp play(state, now) do
    state = Page.advance(state, now)
    _ = Page.render(state)
    game = Map.fetch!(Map.fetch!(state, :match), :game)

    if Map.fetch!(game, :status) == :running,
      do: play(state, now + 100),
      else: Map.fetch!(game, :tick)
  end
end
