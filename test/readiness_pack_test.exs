defmodule GoatwarsPackReadinessTest do
  use ExUnit.Case, async: true
  alias AvmBadgeApps.Pack

  test "the complete GoatWars pack fits the badge and uses its namespace only" do
    beams = Pack.beams!(Mix.Project.compile_path(), "goatwars")
    assert length(beams) == 17
    path = Path.join(System.tmp_dir!(), "goatwars_pack_#{System.unique_integer([:positive])}.avm")
    on_exit(fn -> File.rm(path) end)
    assert :ok = ExAtomVM.PackBEAM.make_avm(Enum.map(beams, &{&1, :beam}), path)
    bytes = File.read!(path)
    assert byte_size(bytes) <= Badge.Store.max_pack()
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    entry = Pack.entry("goatwars", Pack.read_meta!("goatwars"), bytes, Badge.Store.api(), private)
    {:ok, [decoded]} = Badge.Store.decode_manifest(Pack.encode_manifest(%{"apps" => [entry]}))
    assert Badge.Store.installable(decoded, []) == :ok
    assert Badge.Store.verify(decoded, bytes, public) == :ok
    assert Badge.Store.verify(decoded, bytes <> <<0>>, public) == {:error, :size}
  end
end
