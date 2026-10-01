args = System.argv()
Code.prepend_path(hd(args))
out = Enum.at(args, 1)
File.mkdir_p!(out)

for tick <- 1..207 do
  state =
    Enum.reduce(1..max(tick, 1), Badge.App.Goatwars.Page.init(countdown_ms: 0), fn i, state ->
      if tick == 0, do: state, else: Badge.App.Goatwars.Page.advance(state, (i - 1) * 100)
    end)

  items = Badge.App.Goatwars.Page.render(state) ++ [{:rect, 0, 0, 320, 240, 0}]

  lines =
    Enum.map(items, fn
      {:rect, x, y, w, h, c} ->
        "0 #{x} #{y} #{w} #{h} #{c} \n"

      {:text, x, y, :default16px, c, :transparent, label} ->
        "1 #{x} #{y} 0 0 #{c} #{label}\n"

      {:scaled_cropped_image, x, y, w, h, _, sx, sy, cx, cy, [], {:rgba8888, iw, ih, bytes}} ->
        file = Path.join(out, "#{tick}.rgba")
        File.write!(file, bytes)
        "2 #{x} #{y} #{w} #{h} 0 #{sx} #{sy} #{cx} #{cy} #{iw} #{ih} #{file}\n"
    end)

  File.write!(Path.join(out, "#{tick}.scene"), [Integer.to_string(length(items)), "\n", lines])
end
