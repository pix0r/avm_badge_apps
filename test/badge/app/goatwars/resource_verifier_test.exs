Code.require_file(Path.expand("../../../../scripts/goatwars_resources.ex", __DIR__))

defmodule GoatwarsResourceVerifierTest do
  use ExUnit.Case, async: true

  test "only measured dense low-budget OOM failures are expected" do
    assert GoatwarsResources.accepted?([
             {:pro, 32768, :ok},
             {:dense, 65536, {:out_of_memory, ""}},
             {:dense, 131_072, :ok}
           ])

    refute GoatwarsResources.accepted?([{:pro, 32768, :undef}])
    refute GoatwarsResources.accepted?([{:dense, 65536, :badarg}])
    refute GoatwarsResources.accepted?([{:dense, 131_072, {:out_of_memory, ""}}])
  end
end
