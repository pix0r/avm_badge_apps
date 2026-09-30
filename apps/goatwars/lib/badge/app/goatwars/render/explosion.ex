defmodule Badge.App.Goatwars.Render.Explosion do
  @moduledoc "A short cosmetic blast; trail clearing is resolved by Game."
  def new(id, position, age \\ 0), do: %{id: id, position: position, age: age}
end
