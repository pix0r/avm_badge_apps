defmodule Badge.App.Goatwars.Setup.Slot do
  @moduledoc "One player's controller choice and relative-turn key preset."
  def new(id, keys, mode), do: %{id: id, keys: keys, mode: mode}
end
