root = Path.expand("..", __DIR__)
Code.require_file("goatwars_core.exs", __DIR__)

for file <- ~w(art render/interstitial render/layout render/explosion render page/state page),
    do: Code.require_file(Path.join(root, "apps/goatwars/lib/badge/app/goatwars/" <> file <> ".ex"))

ExUnit.start()

defmodule GoatwarsIntegrationTest do
  use ExUnit.Case, async: false
  alias Badge.App.Goatwars.Page
  alias Badge.Store.Installed
  alias Badge.Sim.Display

  setup do
    start_supervised!({Badge.Log, :ok})
    start_supervised!(Badge.Sim.Nvs)
    Agent.update(Badge.Sim.Nvs, fn _ -> %{} end)
    for child <- Badge.Sim.Fakes.children(), do: start_supervised!(child)

    :sys.replace_state(Badge.Wifi, fn state ->
      %{
        state
        | calls: fn :status, _ -> %{radio: :disabled, ip: nil, synced: false, ssid: nil} end
      }
    end)

    for child <- [
          {Badge.Backlight, :ok},
          {Badge.Power, :ok},
          {Badge.Pixels, :sim_spi},
          {Badge.Sensors, :ok},
          Display
        ],
        do: start_supervised!(child)

    start_ui()
    :ok
  end

  test "empty NVS boots and the loaded game plays offline through the real UI" do
    assert Badge.Sim.Nvs.get("badge", "apps") == nil
    install()
    Badge.UI.goto(Page)
    assert :sys.get_state(Badge.UI).page == Page
    tick()
    snapshot = Display.snapshot()
    assert Enum.any?(snapshot.items, &match?({:text, _, _, _, _, _, "Enter: play"}, &1))
    assert length(snapshot.items) == length(snapshot.frame)
    Badge.UI.key_event(Badge.Keymap.decode(~c"Enter", false))
    tick()
    assert Enum.any?(Display.snapshot().items, &match?({:text, _, _, _, _, _, "3"}, &1))
    assert Enum.any?(Display.snapshot().items, &match?({:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, {:rgba8888, 23, 23, _}}, &1))
    Badge.UI.key_event(Badge.Keymap.decode(~c"Left", false))
    assert :sys.get_state(Badge.UI).page_state.match.controllers[1] == :human
    Badge.UI.key_event(Badge.Keymap.decode(~c"S", false))
    tick()
    assert :sys.get_state(Badge.UI).page_state.screen == :settings

    assert Enum.any?(
             Display.snapshot().items,
             &match?({:text, _, _, _, _, _, "PLAYER SETTINGS"}, &1)
           )

    Badge.UI.key_event(Badge.Keymap.decode(~c"Enter", false))
    assert :sys.get_state(Badge.UI).page_state.screen == :game
    Badge.UI.key_event({:nav, :home})
    assert :sys.get_state(Badge.UI).page == Badge.Page.Home
    Badge.UI.goto(Page)
    assert :sys.get_state(Badge.UI).page_state.round == 1
  end

  test "installation survives a fresh UI process and an offline download fails safely" do
    install()
    :ok = stop_supervised(Badge.UI)
    start_ui()
    assert :sys.get_state(Badge.UI).page == Badge.Page.Splash
    Badge.UI.goto(Page)
    assert :sys.get_state(Badge.UI).page == Badge.Page.Store
    tick()
    eventually(fn -> :sys.get_state(Badge.UI).page_state.job == nil end)
    assert :sys.get_state(Badge.UI).page == Badge.Page.Store
    assert Process.alive?(Process.whereis(Badge.UI))
    assert byte_size(Badge.Sim.Nvs.get("badge", "apps")) > 0
    Badge.UI.key_event({:nav, :home})
    assert :sys.get_state(Badge.UI).page == Badge.Page.Home
  end

  test "a failing installed game is disabled while Home remains responsive" do
    install()
    Badge.UI.goto(Page)
    _ = :sys.get_state(Badge.UI)
    :sys.replace_state(Badge.UI, fn ui -> %{ui | page_state: :broken} end)
    tick()
    assert :sys.get_state(Badge.UI).page == Badge.Page.Home
    Badge.UI.goto(Page)
    assert :sys.get_state(Badge.UI).page == Badge.Page.Home
    assert Process.alive?(Process.whereis(Badge.UI))
    assert byte_size(Badge.Sim.Nvs.get("badge", "apps")) > 0
  end

  test "slow UI work cannot accumulate rendering ticks ahead of keys" do
    pid = Process.whereis(Badge.UI)
    :ok = :sys.suspend(pid)

    try do
      Process.sleep(450)
      {:messages, messages} = Process.info(pid, :messages)

      ticks =
        Enum.count(messages, fn
          :render_tick -> true
          {:render_tick, _} -> true
          _ -> false
        end)

      assert ticks <= 1
    after
      :ok = :sys.resume(pid)
    end

    Badge.UI.goto(Page)
    _ = :sys.get_state(Badge.UI)
    Badge.UI.key_event({:nav, :home})
    assert :sys.get_state(Badge.UI).page == Badge.Page.Home
  end

  test "the UI acknowledges fine game cadences and accounts for elapsed sleep time" do
    install()
    Badge.UI.goto(Page)
    ui = :sys.get_state(Badge.UI)

    for interval <- [50, 110, 130, 400] do
      game = Page.init(countdown_ms: 0, rules: %{width: 51, height: 30, step_ms: interval})
      {:noreply, next} = Badge.UI.handle_info({:render_tick, self()}, %{ui | page_state: game})
      assert_receive {:rendered, ^interval}
      assert next.tick_ms == interval
      assert next.countdown == 0
    end

    game = Page.init(countdown_ms: 0, rules: %{width: 51, height: 30, step_ms: 50})
    {:noreply, next} = Badge.UI.handle_info({:render_tick, self()}, %{ui | page_state: game})
    assert_receive {:rendered, 50}
    next = %{next | idle: 0, status_countdown: 100}
    {:noreply, next} = Badge.UI.handle_info({:render_tick, self()}, next)
    assert_receive {:rendered, 50}
    assert next.idle == 5
    assert next.status_countdown == 95

    {:ok, paused} = Page.handle_key({:char, 32}, next.page_state)
    {:noreply, _} = Badge.UI.handle_info({:render_tick, self()}, %{next | page_state: paused})
    assert_receive {:rendered, 100}
  end

  test "game frames do not wait for the backlight settings process" do
    install()
    Badge.UI.goto(Page)
    ui = :sys.get_state(Badge.UI)
    game = Page.init(countdown_ms: 0)
    :ok = :sys.suspend(Badge.Backlight)
    worker = Task.async(fn -> Badge.UI.handle_info({:render_tick, self()}, %{ui | page_state: game, status_countdown: 100}) end)

    try do
      assert {:ok, {:noreply, next}} = Task.yield(worker, 200)
      assert next.page_state.match.game.tick == 1
    after
      :ok = :sys.resume(Badge.Backlight)
      Task.shutdown(worker, :brutal_kill)
    end
  end

  test "sleep timeout updates reach the UI after store and either process restarts" do
    Badge.Backlight.store(100, :off)
    eventually(fn -> :sys.get_state(Badge.UI).sleep_timeout == :off end)
    :ok = stop_supervised(Badge.UI)
    start_ui()
    eventually(fn -> :sys.get_state(Badge.UI).sleep_timeout == :off end)
    :ok = stop_supervised(Badge.Backlight)
    Badge.Sim.Nvs.put("badge", "sleep", "10s")
    start_supervised!({Badge.Backlight, :ok})
    eventually(fn -> :sys.get_state(Badge.UI).sleep_timeout == :s10 end)
    {:noreply, next} = Badge.UI.handle_info(:render_tick, %{:sys.get_state(Badge.UI) | idle: 999, status_countdown: 100})
    assert next.asleep
  end

  defp install do
    :sys.replace_state(Badge.UI, fn ui ->
      entry = %{
        id: "goatwars",
        name: "GoatWars",
        version: "0.1.0",
        size: 62052,
        api: Badge.Store.api(),
        storage: "ram",
        sha256: "",
        sig: ""
      }

      :ok = Installed.put(entry)
      Installed.mark_loaded("goatwars")
      ui
    end)
  end

  defp start_ui, do: start_supervised!({Badge.UI, {Display, Display}})

  defp tick do
    send(Badge.UI, :render_tick)
    :sys.get_state(Badge.UI)
  end

  defp eventually(fun, attempts \\ 50)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
