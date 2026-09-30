defmodule GoatwarsResources do
  alias Badge.App.Goatwars.Page

  def start do
    :io.format(~c"Word size: ~p bytes~n", [:erlang.system_info(:wordsize)])
    fixtures = [:beginner, :intermediate, :expert, :pro, :dense, :lifecycle]
    results = for fixture <- fixtures, limit <- [32_768, 65_536, 131_072], do: run(fixture, limit)
    true = accepted?(results)
    :io.format(~c"Resource fixtures passed at 131072 words~n")
    :ok
  end

  def accepted?(results) do
    Enum.all?(results, fn
      {_, _, :ok} -> true
      {:dense, limit, {:out_of_memory, _}} when limit < 131_072 -> true
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
    occupied = for x <- 0..77, y <- 0..45, do: {{x, y}, rem(x + y, 4) + 1}

    game = %{
      state.match.game
      | occupied: Map.new(occupied),
        trails: Map.new(for id <- 1..4, do: {id, for({position, ^id} <- occupied, do: position)})
    }

    state = %{state | match: %{state.match | game: game}}
    items = Page.render(state)
    true = length(items) > 3500

    true =
      Enum.all?(items, fn
        {:rect, x, y, w, h, _} ->
          x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= 320 and y + h <= 240

        {:text, x, y, :default16px, _, :transparent, label} ->
          x >= 0 and y >= 0 and is_binary(label)
      end)

    {length(items), :erts_debug.flat_size(state), :erts_debug.flat_size(items),
     :erlang.process_info(self(), :heap_size)}
  end

  def fixture(:lifecycle), do: lifecycle(25)

  def fixture(level) do
    state =
      Page.init(countdown_ms: 0, profiles: %{1 => level, 2 => level, 3 => level, 4 => level})

    play(state, 0, 0, 0)
  end

  defp play(state, now, max_items, max_state) do
    state = Page.advance(state, now)
    [] = state.match.replay
    items = Page.render(state)
    max_items = max(max_items, length(items))
    max_state = max(max_state, :erts_debug.flat_size(state))

    if state.match.game.status == :running do
      play(state, now + 100, max_items, max_state)
    else
      {state.match.game.tick, max_items, max_state, :erlang.process_info(self(), :heap_size)}
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
