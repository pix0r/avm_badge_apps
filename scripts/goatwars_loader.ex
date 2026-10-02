defmodule GoatwarsLoader do
  @compile {:no_warn_undefined, [:atomvm, Badge.App.Goatwars.Page]}
  @pack File.read!(System.fetch_env!("GOATWARS_PACK"))
  @imports :erlang.binary_to_term(File.read!(System.fetch_env!("GOATWARS_IMPORTS")))

  def start do
    false = :erlang.function_exported(Badge.App.Goatwars.Page, :init, 0)
    pack = @pack
    true = byte_size(pack) <= 65_536
    :ok = :atomvm.add_avm_pack_binary(pack, name: :goatwars_readiness)

    for {module, function, arity} <- @imports, module != :erlang do
      exports = apply(module, :module_info, [:exports])
      true = :lists.member({function, arity}, exports)
    end

    state = Badge.App.Goatwars.Page.init()
    :loading = Map.fetch!(state, :screen)
    state = Badge.App.Goatwars.Page.advance(state, 0)
    :loading = Map.fetch!(state, :screen)
    true = length(Badge.App.Goatwars.Page.render(state)) > 0
    state = Badge.App.Goatwars.Page.advance(state, 100)
    :title = Map.fetch!(state, :screen)
    true = length(Badge.App.Goatwars.Page.render(state)) > 0
    {:ok, state} = Badge.App.Goatwars.Page.handle_key(:enter, state)
    state = state |> Badge.App.Goatwars.Page.advance(0) |> Badge.App.Goatwars.Page.advance(3000)
    true = state.started
    true = length(Badge.App.Goatwars.Page.render(state)) > 0
    :ok = Badge.App.Goatwars.Page.leave(state)
    :io.format(~c"Actual Store pack loaded and played on AtomVM~n")
    :ok
  end
end
