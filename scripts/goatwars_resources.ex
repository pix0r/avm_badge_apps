defmodule GoatwarsResources do
  alias Badge.App.Goatwars.{Page, Render}
  @coarse %{width: 24, height: 14, explosion_radius: 2, retract_speed: 8}
  @middle %{width: 51, height: 30, explosion_radius: 2, retract_speed: 8}
  @full %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8}

  def start do
    :io.format(~c"Word size: ~p bytes~n", [:erlang.system_info(:wordsize)])
    fixtures = [:beginner, :intermediate, :expert, :pro, :fullsize, :reported_state, :dense, :lifecycle, :soak, :middle_soak, :full_soak]
    results = for fixture <- fixtures, limit <- [4096, 8192, 16384], do: run(fixture, limit)
    results = [run(:queue, 32768), run(:coarse_queue, 32768), run(:full_queue, 32768) | results]
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

    %{width: width, height: height} = state.match.game.config

    rows =
      for y <- 0..(height - 1) do
        pixels = for x <- 0..(width - 1), do: <<Render.color(rem(x + y, 4) + 1)::24, 255>>
        :erlang.list_to_binary(pixels)
      end

    game = %{state.match.game | occupied: {width, height, :erlang.list_to_binary(rows)}}

    state = %{state | match: %{state.match | game: game}}
    items = Page.render(state)
    true = length(items) < 60

    true =
      Enum.all?(items, fn
        {:rect, x, y, w, h, _} ->
          x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= 320 and y + h <= 240

        {:text, x, y, :default16px, _, background, label} ->
          x >= 0 and y >= 0 and is_binary(label) and (background == :transparent or background == 0x241332)

        {:scaled_cropped_image, x, y, w, h, _, _, _, _, _, [], {:rgba8888, iw, ih, bytes}} ->
          x >= 0 and y >= 0 and x + w <= 320 and y + h <= 240 and byte_size(bytes) == iw * ih * 4
      end)

    {length(items), :erts_debug.flat_size(state), :erts_debug.flat_size(items), :erlang.process_info(self(), :heap_size)}
  end

  def fixture(:lifecycle), do: lifecycle(25)
  def fixture(:soak), do: soak(100, 0, 0, @coarse)
  def fixture(:middle_soak), do: soak(100, 0, 0, @middle)
  def fixture(:full_soak), do: soak(100, 0, 0, @full)
  def fixture(:queue), do: queued(Page.init(countdown_ms: 0), 0, [], 0)
  def fixture(:coarse_queue), do: queued(Page.init(countdown_ms: 0, rules: @coarse), 0, [], 0)
  def fixture(:full_queue), do: queued(Page.init(countdown_ms: 0, rules: @full), 0, [], 0)
  def fixture(:fullsize), do: play(Page.init(countdown_ms: 0, rules: @full), 0, 0, 0, 0)

  def fixture(:reported_state) do
    state = Enum.reduce(:lists.seq(0, 96), Page.init(countdown_ms: 0, rules: @full), fn tick, state -> Page.advance(state, tick * 100) end)
    2425 = Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :scores), 1)
    2425 = Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :scores), 4)
    game = Map.fetch!(Map.fetch!(state, :match), :game)
    147 = Map.fetch!(Map.fetch!(game, :arena), :next_shrink_tick) - Map.fetch!(game, :tick)
    true = length(Page.render(state)) > 0
    98 = Map.fetch!(Map.fetch!(Map.fetch!(Page.advance(state, 9700), :match), :game), :tick)
    :ok
  end

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

  defp soak(0, max_state, max_binary, _rules), do: {100, max_state, max_binary, :erlang.memory(:binary)}

  defp soak(n, max_state, max_binary, rules) do
    {_, _, words, _, bytes} = play(Page.init(countdown_ms: 0, seed: n, rules: rules), 0, 0, 0, 0)
    true = words < 800
    soak(n - 1, max(max_state, words), max(max_binary, bytes), rules)
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
    :title = Map.fetch!(state, :screen)
    true = length(Page.render(state)) > 0
    {:ok, state} = Page.handle_key(:enter, state)
    state = state |> Page.advance(0) |> Page.advance(3000)
    {:ok, state} = Page.handle_key({:move, :left}, state)
    {:ok, state} = Page.handle_key({:char, ?s}, state)
    {:ok, state} = Page.handle_key({:char, ?c}, state)
    {:ok, state} = Page.handle_key({:char, ?g}, state)
    {:ok, state} = Page.handle_key({:char, ?f}, state)
    {:ok, state} = Page.handle_key({:edit, :newline}, state)
    true = length(Page.render(state)) > 0
    :ok = Page.leave(state)
    lifecycle(n - 1)
  end
end
