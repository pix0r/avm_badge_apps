defmodule Badge.App.Goatwars.SetupTest.GuestPilot do
  @behaviour Badge.App.Goatwars.Controller

  @impl true
  def init(seed), do: seed

  @impl true
  def choose(_public_game, _id, memory), do: {:left, memory + 1}
end
