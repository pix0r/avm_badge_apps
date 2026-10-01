defmodule GoatwarsUsbLoader do
  @compile {:no_warn_undefined, [:atomvm, Badge.App.Goatwars.Page]}
  @main File.read!(Path.join(System.fetch_env!("GOATWARS_USB_OUTPUT"), "firmware.avm"))
  @assets File.read!(Path.join(System.fetch_env!("GOATWARS_USB_OUTPUT"), "assets.avm"))

  def start do
    :ok = :atomvm.add_avm_pack_binary(@main, name: :goatwars_usb_main)
    :ok = :atomvm.add_avm_pack_binary(@assets, name: :goatwars_usb_assets)
    state = Badge.App.Goatwars.Page.init(countdown_ms: 0)
    {51, 30, bytes} = Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :game), :occupied)
    6120 = byte_size(bytes)
    middle_result = play(state, 0)
    ^middle_result = play(Badge.App.Goatwars.Page.init(countdown_ms: 0), 0)
    coarse = Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: 24, height: 14, explosion_radius: 2, retract_speed: 8})
    {_tick, _scores, _status} = play(coarse, 0)
    full = Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8})
    {_tick, _scores, _status} = play(full, 0)
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
