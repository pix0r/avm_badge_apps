defmodule GoatwarsUsbLoader do
  @compile {:no_warn_undefined, [:atomvm, Badge.App.Goatwars.Page]}
  @main File.read!(Path.join(System.fetch_env!("GOATWARS_USB_OUTPUT"), "firmware.avm"))
  @assets File.read!(Path.join(System.fetch_env!("GOATWARS_USB_OUTPUT"), "assets.avm"))

  def start do
    :ok = :atomvm.add_avm_pack_binary(@main, name: :goatwars_usb_main)
    :ok = :atomvm.add_avm_pack_binary(@assets, name: :goatwars_usb_assets)
    state = Badge.App.Goatwars.Page.init(countdown_ms: 0)
    {23, 23, bytes} = Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :occupied)
    2116 = byte_size(bytes)
    for started <- [true, false] do
      input = %{state | started: started, launch_at: :erlang.monotonic_time(:millisecond) - 1}
      :ignore = Badge.App.Goatwars.Page.handle_key({:move, :left}, input)
      waiting = Badge.App.Goatwars.Page.tick(input)
      0 = waiting.match.game.tick
      receive do
        {:goatwars_step, _, _, _, _} = message ->
          {:ok, stepped} = Badge.App.Goatwars.Page.handle_info(message, waiting)
          :west = stepped.match.game.players[1].direction
      end
    end
    middle_result = play(state, 0)
    ^middle_result = play(Badge.App.Goatwars.Page.init(countdown_ms: 0), 0)

    for {width, height} <- [{14, 14}, {30, 30}, {46, 46}, {24, 14}, {39, 23}, {51, 30}, {78, 46}] do
      state = Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: width, height: height, explosion_radius: 2, retract_speed: 8})
      {_tick, _scores, _status} = play(state, 0)
    end

    :io.format(~c"Actual split USB images loaded and played on AtomVM~n")
    :ok
  end

  defp play(state, now) do
    state = Badge.App.Goatwars.Page.advance(state, now)
    items = Badge.App.Goatwars.Page.render(state)
    true = length(items) > 0
    game = Map.fetch!(Map.fetch!(state, :match), :game)
    tick = Map.fetch!(game, :tick)

    true = tick < 5000
    status = Map.fetch!(game, :status)

    if status == :running do
      play(state, now + 100)
    else
      true = status == :draw or is_tuple(status)
      {tick, Map.fetch!(Map.fetch!(state, :match), :scores), status}
    end
  end
end
