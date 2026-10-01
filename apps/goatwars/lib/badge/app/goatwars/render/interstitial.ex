defmodule Badge.App.Goatwars.Render.Interstitial do
  @moduledoc "Shared goat artwork and scenery for opening and between-round screens."

  @bg 0x241332
  @mint 0x5DE2B4
  @coral 0xFF7A90
  @cream 0xFFF5CC

  @scenery (for {x, y, color} <- [
                  {12, 38, @mint},
                  {304, 46, @coral},
                  {28, 112, @cream},
                  {292, 106, @mint},
                  {44, 70, @coral},
                  {278, 72, @cream}
                ] do
              {:rect, x, y, 2, 2, color}
            end) ++
             [
               {:rect, 260, 126, 38, 5, @coral},
               {:rect, 254, 134, 50, 5, @coral},
               {:rect, 256, 142, 46, 5, @coral},
               {:rect, 262, 150, 34, 4, @coral},
               {:rect, 0, 165, 320, 1, @coral},
               {:rect, 0, 181, 320, 1, 0x4D2B63},
               {:rect, 0, 203, 320, 1, 0x4D2B63},
               {:rect, 24, 165, 1, 44, 0x4D2B63},
               {:rect, 296, 165, 1, 44, 0x4D2B63}
             ]

  def title(%{goat: goat, logo: logo}) do
    [
      image(16, 32, logo),
      text(88, 98, "DON'T LET IT CRASH", @mint),
      text(208, 158, "Enter: play", @cream),
      text(208, 182, "S: settings", @mint),
      image(8, 110, goat)
      | @scenery ++ [{:rect, 0, 24, 320, 216, @bg}]
    ]
  end

  def scene(%{goat: goat}, title, hint, color) do
    [
      text(div(320 - byte_size(title) * 8, 2), 34, title, color),
      text(div(320 - byte_size(hint) * 8, 2), 54, hint, @cream),
      image(64, 76, goat)
      | @scenery ++ [{:rect, 0, 24, 320, 185, @bg}]
    ]
  end

  defp image(x, y, {:rgba8888, width, height, _} = image) do
    {:scaled_cropped_image, x, y, width * 2, height * 2, @bg, 0, 0, 2, 2, [], image}
  end

  defp text(x, y, label, color), do: {:text, x, y, :default16px, color, @bg, label}
end
