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
    90 = play(state, 0)
    coarse = Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: 24, height: 14, explosion_radius: 2, retract_speed: 8})
    91 = play(coarse, 0)
    full = Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8})
    207 = play(full, 0)
    :io.format(~c"Actual split USB images loaded and played on AtomVM~n")
    :ok
  end

  defp play(state, now) do
    state = Badge.App.Goatwars.Page.advance(state, now)
    items = Badge.App.Goatwars.Page.render(state)
    true = length(items) > 0
    game = Map.fetch!(Map.fetch!(state, :match), :game)
    tick = Map.fetch!(game, :tick)

    if tick == 97 do
      2425 = Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :scores), 1)
      2425 = Map.fetch!(Map.fetch!(Map.fetch!(state, :match), :scores), 4)
    end

    if Map.fetch!(game, :status) == :running, do: play(state, now + 100), else: tick
  end
end
