root = Path.expand("..", __DIR__)
Code.require_file("goatwars_core.exs", __DIR__)
for file <- ~w(render/layout render/explosion render page/state page),
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
    assert Enum.any?(snapshot.items, &match?({:text, _, _, _, _, _, "READY"}, &1))
    assert length(snapshot.items) == length(snapshot.frame)
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
