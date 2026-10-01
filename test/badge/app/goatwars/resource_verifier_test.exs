Code.require_file(Path.expand("../../../../scripts/goatwars_resources.ex", __DIR__))

defmodule GoatwarsResourceVerifierTest do
  use ExUnit.Case, async: true

  test "every optimized fixture must finish without an OOM or other exit" do
    assert GoatwarsResources.accepted?([
             {:pro, 32768, :ok},
             {:dense, 4096, :ok},
             {:dense, 131_072, :ok}
           ])

    refute GoatwarsResources.accepted?([{:dense, 4096, {:out_of_memory, ""}}])
    refute GoatwarsResources.accepted?([{:pro, 32768, :undef}])
    refute GoatwarsResources.accepted?([{:dense, 65536, :badarg}])
    refute GoatwarsResources.accepted?([{:dense, 131_072, {:out_of_memory, ""}}])
  end
end
