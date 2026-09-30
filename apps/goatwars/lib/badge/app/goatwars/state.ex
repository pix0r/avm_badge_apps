defmodule Badge.App.Goatwars.State do
  @moduledoc "Complete, serializable round state. No clocks, processes or UI data."
  alias Badge.App.Goatwars.{Arena, Config, Player}

  def new(%{config: _, arena: _, players: _, occupied: _} = fields) do
    Map.merge(%{trails: %{}, tick: 0, status: :running}, fields)
  end

  @type status :: :running | :draw | {:winner, integer()}
  @type t :: %{
          config: Config.t(),
          arena: Arena.t(),
          players: %{integer() => Player.t()},
          occupied: %{Player.position() => integer()},
          trails: %{integer() => [Player.position()]},
          tick: non_neg_integer(),
          status: status()
        }
end
