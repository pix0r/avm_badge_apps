defmodule Badge.App.Beamwars.State do
  @moduledoc "Complete, serializable round state. No clocks, processes or UI data."
  alias Badge.App.Beamwars.{Arena, Config, Player}

  @enforce_keys [:config, :arena, :players, :occupied]
  defstruct [:config, :arena, :players, :occupied, tick: 0, status: :running]

  @type status :: :running | :draw | {:winner, integer()}
  @type t :: %__MODULE__{
          config: Config.t(),
          arena: Arena.t(),
          players: %{integer() => Player.t()},
          occupied: %{Player.position() => integer()},
          tick: non_neg_integer(),
          status: status()
        }
end
