args = System.argv()
Code.prepend_path(hd(args))
out = Enum.at(args, 1)
File.mkdir_p!(out)

defmodule GoatwarsRasterExport do
  def write(state, out, label) do
    items = Badge.App.Goatwars.Page.render(state) ++ [{:rect, 0, 0, 320, 240, 0}]

    lines =
      Enum.with_index(items)
      |> Enum.map(fn
        {{:rect, x, y, w, h, c}, _index} ->
          "0 #{x} #{y} #{w} #{h} #{c} \n"

        {{:text, x, y, :default16px, c, :transparent, label}, _index} ->
          "1 #{x} #{y} 0 0 #{c} #{label}\n"

        {{:text, x, y, :default16px, c, background, label}, _index} when is_integer(background) ->
          "3 #{x} #{y} 0 0 #{c} #{background} #{label}\n"

        {{:scaled_cropped_image, x, y, w, h, background, sx, sy, cx, cy, [], {:rgba8888, iw, ih, bytes}}, index} ->
          file = Path.join(out, "#{label}-#{index}.rgba")
          File.write!(file, bytes)
          "2 #{x} #{y} #{w} #{h} #{if is_integer(background), do: background, else: 0} #{sx} #{sy} #{cx} #{cy} #{iw} #{ih} #{file}\n"
      end)

    File.write!(Path.join(out, "#{label}.scene"), [Integer.to_string(length(items)), "\n", lines])
  end

  def play(state, out, tick \\ 1) do
    state = Badge.App.Goatwars.Page.advance(state, (tick - 1) * 100)
    write(state, out, tick)

    if state.match.game.status == :running,
      do: play(state, out, tick + 1),
      else: File.write!(Path.join(out, "frames"), Integer.to_string(tick))
  end
end

GoatwarsRasterExport.play(
  Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8}),
  out
)

for {width, height} <- [{14, 14}, {23, 23}, {30, 30}, {46, 46}, {24, 14}, {39, 23}, {51, 30}, {78, 46}] do
  state =
    Enum.reduce(
      0..3,
      Badge.App.Goatwars.Page.init(countdown_ms: 0, rules: %{width: width, height: height, explosion_radius: 2, retract_speed: 8}),
      fn i, state -> Badge.App.Goatwars.Page.advance(state, i * 100) end
    )

  GoatwarsRasterExport.write(state, out, "#{width}x#{height}")
end
