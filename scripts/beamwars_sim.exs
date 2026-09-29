Code.require_file("beamwars_core.exs", __DIR__)
Code.require_file(Path.expand("../apps/beamwars/lib/render.ex", __DIR__))
Code.require_file(Path.expand("../apps/beamwars/lib/page.ex", __DIR__))

# Register the development page without changing the firmware checkout.
pages = [Badge.App.Beamwars.Page | Badge.Pages.all()]
keys = Badge.Pages.keys()
Code.compiler_options(ignore_module_conflict: true)

Code.compile_quoted(
  quote do
    defmodule Badge.Pages do
      @pages unquote(pages)
      @keys unquote(keys)
      def all, do: @pages
      def keys, do: @keys
      def screens, do: div(length(@pages) + length(@keys) - 1, length(@keys))

      def screen(index),
        do: Enum.zip(@keys, Enum.take(Enum.drop(@pages, index * length(@keys)), length(@keys)))

      def for_key(key), do: for_key(key, 0)
      def for_key(key, index), do: Keyword.get(screen(index), key)
    end
  end
)

Code.compiler_options(ignore_module_conflict: false)
Badge.Backlight.store(80, :off)
Badge.UI.goto(Badge.App.Beamwars.Page)

IO.puts(
  "BeamWars ready: http://localhost:3240 | Space pause | r rematch | b AI | arrows/A-D/J-L/V-N steer"
)
