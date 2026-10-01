args = System.argv()
Code.prepend_path(hd(args))
out = Enum.at(args, 1)
File.mkdir_p!(out)

defmodule GoatwarsRasterExport do
  def write(state, out, label) do
    items = Badge.App.Goatwars.Page.render(state) ++ [{:rect, 0, 0, 320, 240, 0}]

    lines =
      Enum.map(items, fn
        {:rect, x, y, w, h, c} ->
          "0 #{x} #{y} #{w} #{h} #{c} \n"

        {:text, x, y, :default16px, c, :transparent, label} ->
          "1 #{x} #{y} 0 0 #{c} #{label}\n"

        {:text, x, y, :default16px, c, background, label} when is_integer(background) ->
          "3 #{x} #{y} 0 0 #{c} #{background} #{label}\n"

        {:scaled_cropped_image, x, y, w, h, _, sx, sy, cx, cy, [], {:rgba8888, iw, ih, bytes}} ->
          file = Path.join(out, "#{label}.rgba")
          File.write!(file, bytes)
          "2 #{x} #{y} #{w} #{h} 0 #{sx} #{sy} #{cx} #{cy} #{iw} #{ih} #{file}\n"
      end)

    File.write!(Path.join(out, "#{label}.scene"), [Integer.to_string(length(items)), "\n", lines])
  end
end

for tick <- 1..207 do
  state =
    Enum.reduce(
      1..tick,
      Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8}),
      fn i, state ->
        Badge.App.Goatwars.Page.advance(state, (i - 1) * 100)
      end
    )

  GoatwarsRasterExport.write(state, out, tick)
end

for {width, height} <- [{24, 14}, {78, 46}] do
  state =
    Enum.reduce(
      0..3,
      Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: width, height: height, explosion_radius: 2, retract_speed: 8}),
      fn i, state ->
        Badge.App.Goatwars.Page.advance(state, i * 100)
      end
    )

  GoatwarsRasterExport.write(state, out, "#{width}x#{height}")
end
