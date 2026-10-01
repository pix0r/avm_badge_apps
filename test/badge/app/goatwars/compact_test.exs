defmodule Badge.App.Goatwars.CompactTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Board, Game, Match, Page, Render, SimpleBot}

  test "compact physics preserves simultaneous collisions, blasts and retraction" do
    reference = Page.init(countdown_ms: 0, compact: false).match
    compact = %{reference | game: Game.compact(reference.game)}

    Enum.reduce(1..300, {reference, compact}, fn _, {reference, compact} ->
      reference = Match.tick(reference)
      compact = Match.tick(compact)
      assert compact.game.players == reference.game.players
      assert compact.game.arena == reference.game.arena
      assert compact.game.status == reference.game.status
      assert compact.events == reference.events
      assert compact.scores == reference.scores
      assert expand(compact.game).occupied == reference.game.occupied
      assert expand(compact.game).trails == reference.game.trails
      layout = Render.layout(reference.game.config)
      actual = Render.scene(compact.game, layout)
      expected = Render.scene(reference.game, layout)

      for {position, _} <- reference.game.occupied do
        {x, y} = position

        assert pixel(actual, layout.x + x * layout.cell + 2, layout.y + y * layout.cell + 2) ==
                 pixel(expected, layout.x + x * layout.cell + 2, layout.y + y * layout.cell + 2)
      end

      {reference, compact}
    end)
  end

  test "compact contraction sweeps edge bikes and crops the bitmap" do
    rules = %{width: 14, height: 10, shrink_after: 1, explosion_radius: 2, retract_speed: 3}
    reference = Match.demo(rules).game
    compact = Game.compact(reference)
    {:ok, reference, events} = Game.step(reference, %{})
    {:ok, compact, actual_events} = Game.step(compact, %{})
    assert {:arena_shrank, 1} in events
    assert actual_events == events
    assert compact.players == reference.players
    assert compact.status == :draw
    assert expand(compact).occupied == reference.occupied
    layout = Render.layout(reference.config)
    x = layout.x + layout.cell
    y = layout.y + layout.cell
    w = 12 * layout.cell
    h = 8 * layout.cell
    cell = layout.cell

    assert {:scaled_cropped_image, ^x, ^y, ^w, ^h, :transparent, 1, 1, ^cell, ^cell, [], {:rgba8888, 14, 10, _}} =
             Enum.find(
               Render.scene(compact, layout),
               &match?({:scaled_cropped_image, _, _, _, _, _, _, _, _, _, _, _}, &1)
             )

    Enum.reduce(1..20, {reference, compact}, fn _, {reference, compact} ->
      reference = Game.cleanup(reference)
      compact = Game.cleanup(compact)
      assert expand(compact).occupied == reference.occupied
      assert expand(compact).trails == reference.trails
      {reference, compact}
    end)
  end

  test "badge survives tick97 with a small retained heap and deterministic scores" do
    state =
      Enum.reduce(
        0..96,
        Page.init(countdown_ms: 0, rules: %{width: 78, height: 46, explosion_radius: 2, retract_speed: 8}),
        &Page.advance(&2, &1 * 100)
      )

    assert state.match.game.tick == 97
    assert state.match.scores[1] == 2425
    assert state.match.scores[4] == 2425
    assert state.match.game.arena.next_shrink_tick - state.match.game.tick == 147
    assert :erts_debug.flat_size(state) < 1300
    assert Page.render(state) != []
    assert Page.advance(state, 9700).match.game.tick == 98
  end

  test "compact bounds checks reject all outside coordinates without wrapping rows" do
    reference = Match.demo(%{width: 8, height: 6}, 1, %{1 => {SimpleBot, SimpleBot.init(1)}}).game
    compact = Game.compact(reference)

    for x <- [-1, 8], y <- [-1, 0, 5, 6] do
      player = %{compact.players[1] | position: {x, y}}
      assert {:ok, _, _} = Game.step(%{compact | players: Map.put(compact.players, 1, player)}, %{})
    end
  end

  defp expand(%{occupied: {w, h, _} = board} = game) do
    occupied = for x <- 0..(w - 1), y <- 0..(h - 1), id = Board.get(board, {x, y}), id != nil, into: %{}, do: {{x, y}, id}
    trails = Map.new(game.trails, fn {id, bytes} -> {id, for(<<x::16, y::16 <- bytes>>, do: {x, y})} end)
    %{game | occupied: occupied, trails: trails}
  end

  defp expand(game), do: game

  defp pixel([], _, _), do: nil

  defp pixel([{:rect, x, y, w, h, c} | _], px, py)
       when px >= x and px < x + w and py >= y and py < y + h,
       do: c

  defp pixel([{:scaled_cropped_image, x, y, w, h, _, sx, sy, cx, cy, [], {:rgba8888, iw, _, bytes}} | _], px, py)
       when px >= x and px < x + w and py >= y and py < y + h do
    offset = ((sy + div(py - y, cy)) * iw + sx + div(px - x, cx)) * 4
    <<_::binary-size(offset), color::24, _::8, _::binary>> = bytes
    color
  end

  defp pixel([_ | rest], x, y), do: pixel(rest, x, y)
end
