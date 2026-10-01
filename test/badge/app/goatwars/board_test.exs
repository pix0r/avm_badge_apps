defmodule Badge.App.Goatwars.BoardTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.Board

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
