defmodule Badge.App.Goatron.Controller do
  @moduledoc """
  A pure input source. Controllers see the same pre-step state and return a turn
  or nil. Controller memory stays in the runner and never enters game state.
  """
  alias Badge.App.Goatron.{Player, State}

  @callback init(integer()) :: term()
  @callback choose(State.t(), integer(), term()) :: {Player.turn(), term()}
end
