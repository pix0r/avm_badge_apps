defmodule Badge.App.Goatwars.BoardTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.Board

  test "bitmap reads reject partial pixels and similar colors with a different byte" do
    for pixel <- [<<200, 64, 255, 0>>, <<200, 65, 255, 255>>, <<0, 255, 137, 255>>, <<255, 40, 93, 255>>, <<112, 65, 255, 255>>, <<200, 64, 255>>] do
      assert Board.get({1, 1, pixel}, {0, 0}) == nil
    end
    board = Board.new(%{width: 2, height: 2}, %{{1, 1} => 4})
    for cell <- [{-1, 0}, {0, -1}, {2, 0}, {0, 2}], do: assert(Board.get(board, cell) == nil)
    assert Board.get({2, 2, <<200, 64, 255, 255>>}, {0, 0}) == 1
    assert Board.get({2, 2, <<200, 64, 255, 255>>}, {1, 0}) == nil
  end

  test "empty bitmap cells use the opaque Elixir purple background" do
    board = Board.new(%{width: 3, height: 2}, %{})
    assert board == {3, 2, :binary.copy(<<61, 23, 90, 255>>, 6)}
    refute Board.has?(board, {1, 1})
  end

  test "all four complementary trail colors encode and decode their player IDs" do
    pixels = [<<200, 64, 255, 255>>, <<0, 255, 136, 255>>, <<255, 40, 92, 255>>, <<112, 64, 255, 255>>]
    bytes = IO.iodata_to_binary(pixels)
    board = Board.new(%{width: 4, height: 1}, %{})

    encoded = Enum.reduce(1..4, board, fn id, board -> Board.put(board, {id - 1, 0}, id) end)
    assert encoded == {4, 1, bytes}
    assert Board.new(%{width: 4, height: 1}, %{{0, 0} => 1, {1, 0} => 2, {2, 0} => 3, {3, 0} => 4}) == encoded

    for id <- 1..4 do
      assert Board.get({4, 1, bytes}, {id - 1, 0}) == id
      assert Board.has?(encoded, {id - 1, 0})
      assert Board.put(encoded, {id - 1, 0}, id) === encoded
    end
  end

  test "single and batch deletion restore purple while keeping neighboring player IDs" do
    board = Board.new(%{width: 4, height: 1}, %{{0, 0} => 1, {1, 0} => 2, {2, 0} => 3, {3, 0} => 4})
    single = Board.delete(board, {1, 0})
    assert single == {4, 1, <<200, 64, 255, 255, 61, 23, 90, 255, 255, 40, 92, 255, 112, 64, 255, 255>>}
    assert Board.get(single, {1, 0}) == nil
    assert Board.get(single, {2, 0}) == 3

    cleared = Board.delete_many(single, [{3, 0}, {0, 0}, {3, 0}])
    assert cleared == {4, 1, <<61, 23, 90, 255, 61, 23, 90, 255, 255, 40, 92, 255, 61, 23, 90, 255>>}
    assert Board.get(cleared, {2, 0}) == 3
    for cell <- [{0, 0}, {1, 0}, {3, 0}], do: assert(Board.get(cleared, cell) == nil)
  end

  test "batch clearing handles unordered duplicates and edges without erasing neighbors" do
    occupied = %{{0, 0} => 1, {3, 0} => 2, {0, 1} => 3, {3, 2} => 4, {2, 2} => 2}
    board = Board.new(%{width: 4, height: 3}, occupied)
    cells = [{3, 2}, {0, 0}, {3, 0}, {3, 2}, {-1, 1}, {4, 0}, {0, 3}, {2, 0}]
    cleared = Board.delete_many(board, cells)
    assert {4, 3, bytes} = cleared
    assert byte_size(bytes) == 48
    for cell <- [{3, 2}, {0, 0}, {3, 0}], do: assert(Board.get(cleared, cell) == nil)
    assert Board.get(cleared, {0, 1}) == 3
    assert Board.get(cleared, {2, 2}) == 2
    assert Board.get(board, {0, 0}) == 1
    assert Board.delete_many(occupied, cells) == %{{0, 1} => 3, {2, 2} => 2}
  end

  test "clearing no occupied cells preserves the original bitmap" do
    board = Board.new(%{width: 4, height: 3}, %{{0, 0} => 1})
    assert Board.delete_many(board, []) === board
    assert Board.delete_many(board, [{-1, 0}, {4, 0}, {1, 1}]) === board
    assert :erts_debug.same(elem(Board.delete_many(board, [{1, 1}]), 2), elem(board, 2))
  end
end
