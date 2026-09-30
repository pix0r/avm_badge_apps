defmodule SourceLayoutTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  test "each source file defines one module at its namespace path" do
    files = Path.wildcard(Path.join(@root, "lib/**/*.ex")) ++ Path.wildcard(Path.join(@root, "apps/*/lib/**/*.ex"))

    for path <- files do
      ast = path |> File.read!() |> Code.string_to_quoted!()

      {_ast, modules} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _, [{:__aliases__, _, namespace}, _]} = node, modules ->
            {node, [Module.concat(namespace) | modules]}

          node, modules ->
            {node, modules}
        end)

      assert length(modules) == 1, "#{path} defines #{length(modules)} modules"
      [module] = modules
      expected = Macro.underscore(module) <> ".ex"
      assert String.ends_with?(path, "/lib/" <> expected), "#{path} should end in lib/#{expected}"
    end
  end

  test "the game has the GoatWars store identity and namespace" do
    path = Path.join(@root, "apps/goatwars/app.exs")
    assert File.exists?(path)
    {metadata, _binding} = Code.eval_file(path)
    assert metadata[:name] == "GoatWars"
    refute File.exists?(Path.join(@root, "apps/beamwars"))
    assert File.exists?(Path.join(@root, "apps/goatwars/lib/badge/app/goatwars/page.ex"))
  end
end
