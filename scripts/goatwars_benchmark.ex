defmodule GoatwarsBenchmark do
  alias Badge.App.Goatwars.Page

  def start do
    :io.format(~c"GW_BENCH word_bytes=~p~n", [:erlang.system_info(:wordsize)])

    for tick <- [0, 32, 64, 96, 97, 128, 192] do
      state = build(Page.init(countdown_ms: 0), 0, tick)
      now = tick * 100
      measure(~c"tick", state, fn -> Page.advance(state, now) end)
      measure(~c"render", state, fn -> Page.render(state) end)
      measure(~c"frame", state, fn -> Page.render(Page.advance(state, now)) end)
      :io.format(~c"GW_STATE tick=~p words=~p items=~p~n", [tick, :erts_debug.flat_size(state), length(Page.render(state))])
    end

    started = :erlang.monotonic_time(:microsecond)
    ticks = rounds(5, 0)
    elapsed = :erlang.monotonic_time(:microsecond) - started
    :io.format(~c"GW_ROUND cpu_us=~p ticks=~p rounds=5~n", [elapsed, ticks])
    :ok
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

  defp rounds(0, ticks), do: ticks
  defp rounds(n, ticks), do: rounds(n - 1, ticks + play(Page.init(countdown_ms: 0), 0))

  defp play(state, now) do
    state = Page.advance(state, now)
    _ = Page.render(state)
    game = Map.fetch!(Map.fetch!(state, :match), :game)

    if Map.fetch!(game, :status) == :running,
      do: play(state, now + 100),
      else: Map.fetch!(game, :tick)
  end
end
