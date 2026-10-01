defmodule GoatwarsResources do
  alias Badge.App.Goatwars.{Page, Render}

  def start do
    :io.format(~c"Word size: ~p bytes~n", [:erlang.system_info(:wordsize)])
    fixtures = [:beginner, :intermediate, :expert, :pro, :dense, :lifecycle, :soak]
    results = for fixture <- fixtures, limit <- [4096, 8192, 16384], do: run(fixture, limit)
    results = [run(:queue, 32768) | results]
    true = accepted?(results)
    :io.format(~c"Resource fixtures passed at 4096, 8192 and 16384 words~n")
    :ok
  end

  def accepted?(results) do
    Enum.all?(results, fn
      {_, _, :ok} -> true
      _ -> false
    end)
  end

  def run(fixture, limit) do
    parent = self()

    {pid, ref} =
      :erlang.spawn_opt(
        fn ->
          started = :erlang.monotonic_time(:microsecond)
          stats = fixture(fixture)
          elapsed = :erlang.monotonic_time(:microsecond) - started
          send(parent, {:result, self(), stats, elapsed})
        end,
        [:monitor, {:max_heap_size, limit}]
      )

    receive do
      {:result, ^pid, stats, elapsed} ->
        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
        end

        :io.format(~c"~p cap=~p passed stats=~p elapsed_us=~p~n", [fixture, limit, stats, elapsed])

        {fixture, limit, :ok}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        :io.format(~c"~p cap=~p failed reason=~p~n", [fixture, limit, reason])
        {fixture, limit, reason}
    after
      120_000 ->
        :erlang.exit(pid, :kill)
        :erlang.error({:fixture_timeout, fixture, limit})
    end
  end

  def fixture(:dense) do
    state = Page.init(countdown_ms: 0)

    rows =
      for y <- 0..45 do
        pixels = for x <- 0..77, do: <<Render.color(rem(x + y, 4) + 1)::24, 255>>
        :erlang.list_to_binary(pixels)
      end

    game = %{state.match.game | occupied: {78, 46, :erlang.list_to_binary(rows)}}

    state = %{state | match: %{state.match | game: game}}
    items = Page.render(state)
    true = length(items) < 60

    true =
      Enum.all?(items, fn
        {:rect, x, y, w, h, _} ->
          x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= 320 and y + h <= 240

        {:text, x, y, :default16px, _, :transparent, label} ->
          x >= 0 and y >= 0 and is_binary(label)

        {:scaled_cropped_image, x, y, w, h, _, _, _, _, _, [], {:rgba8888, iw, ih, bytes}} ->
          x >= 0 and y >= 0 and x + w <= 320 and y + h <= 240 and byte_size(bytes) == iw * ih * 4
      end)

    {length(items), :erts_debug.flat_size(state), :erts_debug.flat_size(items), :erlang.process_info(self(), :heap_size)}
  end

  def fixture(:lifecycle), do: lifecycle(25)
  def fixture(:soak), do: soak(100, 0, 0)
  def fixture(:queue), do: queued(Page.init(countdown_ms: 0), 0, [], 0)

  def fixture(level) do
    state =
      Page.init(countdown_ms: 0, profiles: %{1 => level, 2 => level, 3 => level, 4 => level})

    play(state, 0, 0, 0, 0)
  end

  defp play(state, now, max_items, max_state, max_binary) do
    state = Page.advance(state, now)
    [] = state.match.replay
    items = Page.render(state)
    max_items = max(max_items, length(items))
    max_state = max(max_state, :erts_debug.flat_size(state))
    max_binary = max(max_binary, :erlang.memory(:binary))
    true = max_binary < 350_000

    if state.match.game.status == :running do
      play(state, now + 100, max_items, max_state, max_binary)
    else
      {state.match.game.tick, max_items, max_state, :erlang.process_info(self(), :total_heap_size), max_binary}
    end
  end

  defp soak(0, max_state, max_binary), do: {100, max_state, max_binary, :erlang.memory(:binary)}

  defp soak(n, max_state, max_binary) do
    {_, _, words, _, bytes} = play(Page.init(countdown_ms: 0, seed: n), 0, 0, 0, 0)
    true = words < 800
    soak(n - 1, max(max_state, words), max(max_binary, bytes))
  end

  defp queued(state, now, queue, max_binary) do
    state = Page.advance(state, now)
    queue = :lists.sublist([Page.render(state) | queue], 32)
    max_binary = max(max_binary, :erlang.memory(:binary))
    true = max_binary < 1_000_000

    if state.match.game.status == :running do
      queued(state, now + 100, queue, max_binary)
    else
      {length(queue), :erts_debug.flat_size(queue), max_binary}
    end
  end

  defp lifecycle(0), do: :ok

  defp lifecycle(n) do
    state = Page.init()
    state = state |> Page.advance(0) |> Page.advance(3000)
    {:ok, state} = Page.handle_key({:move, :left}, state)
    {:ok, state} = Page.handle_key({:char, ?s}, state)
    {:ok, state} = Page.handle_key({:char, ?c}, state)
    {:ok, state} = Page.handle_key({:edit, :newline}, state)
    true = length(Page.render(state)) > 0
    :ok = Page.leave(state)
    lifecycle(n - 1)
  end
end
