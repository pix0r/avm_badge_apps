defmodule Badge.App.Goatwars.SimpleBotTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Arena, Board, Game, Player, SimpleBot}

  test "keeps heading when the next cell is clear" do
    game = game()
    memory = SimpleBot.init(1, :pro)
    {turn, updated} = SimpleBot.choose(game, 1, memory)
    assert turn == nil
    assert updated.profile == memory.profile
  end

  test "turns around a trail and chooses the other side if its preferred side is blocked" do
    game = game()
    memory = SimpleBot.init(1, :pro)
    game = %{game | occupied: Map.put(game.occupied, {5, 4}, 2)}
    {turn, _} = SimpleBot.choose(game, 1, memory)
    assert turn == :left or turn == :right
    blocked = Player.move(game.players[1], turn).position
    game = %{game | occupied: Map.put(game.occupied, blocked, 2)}
    {other, _} = SimpleBot.choose(game, 1, memory)
    assert other != turn and (other == :left or other == :right)
  end

  test "avoids the ring that contracts before the next move" do
    game = game()

    game = %{
      game
      | players: Map.put(game.players, 1, %{game.players[1] | position: {1, 4}, direction: :west}),
        config: %{game.config | shrink_after: 1},
        arena: %{game.arena | next_shrink_tick: 1}
    }

    {turn, _} = SimpleBot.choose(game, 1, SimpleBot.init(2))
    assert turn == :left or turn == :right
  end

  test "lays a trail across an opponent's projected route instead of keeping heading" do
    game = %{game() | players: Map.put(game().players, 2, %{game().players[2] | position: {7, 6}})}
    game = %{game | occupied: %{{4, 4} => 1, {7, 6} => 2}}

    for seed <- 1..16 do
      assert {:right, _} = SimpleBot.choose(game, 1, SimpleBot.init(seed, :pro))
    end
  end

  test "avoids a clear cell with no onward escape before pursuing or jittering" do
    game = game()
    occupied = Map.merge(game.occupied, %{{6, 4} => 2, {5, 3} => 2, {5, 5} => 2})
    game = %{game | occupied: occupied}

    for seed <- 1..32 do
      {turn, _} = SimpleBot.choose(game, 1, SimpleBot.init(seed, :pro))
      assert turn == :left or turn == :right
    end
  end

  test "avoids an opponent's next head when another move is safe" do
    game = game()
    game = %{game | players: Map.put(game.players, 2, %{game.players[2] | position: {6, 4}}), occupied: %{{4, 4} => 1, {6, 4} => 2}}

    for seed <- 1..32 do
      {turn, _} = SimpleBot.choose(game, 1, SimpleBot.init(seed, :pro))
      assert turn == :left or turn == :right
    end
  end

  test "seeded choices vary on comparable safe routes and remain reproducible" do
    game = game()
    game = %{game | players: Map.put(game.players, 2, %{game.players[2] | alive: false})}

    turns =
      for seed <- 1..64 do
        memory = SimpleBot.init(seed, aggression: 0)
        decision = SimpleBot.choose(game, 1, memory)
        assert decision == SimpleBot.choose(game, 1, memory)
        elem(decision, 0)
      end

    assert MapSet.new(turns) == MapSet.new([nil, :left, :right])
  end

  test "each decision advances a small seed without changing custom profiles" do
    game = game()
    memory = SimpleBot.init(134_217_726, aggression: 3, prediction_ticks: 4)
    {_, next} = SimpleBot.choose(game, 1, memory)
    {_, later} = SimpleBot.choose(game, 1, next)
    assert next.seed != memory.seed
    assert later.seed != next.seed
    assert next.seed >= 0 and next.seed < 134_217_728
    assert later.seed >= 0 and later.seed < 134_217_728
    assert next.profile == memory.profile
    assert later.profile == memory.profile
    fixed = SimpleBot.init(312_475)
    {_, advanced} = SimpleBot.choose(game, 1, fixed)
    assert advanced.seed != fixed.seed
  end

  test "seeded safety and attacks agree for map and bitmap boards" do
    game = game()
    game = %{game | occupied: Map.merge(game.occupied, %{{5, 4} => 2, {4, 3} => 3})}
    bitmap = Game.compact(game)

    for seed <- 1..32 do
      memory = SimpleBot.init(seed)
      assert SimpleBot.choose(bitmap, 1, memory) == SimpleBot.choose(game, 1, memory)
      {turn, _} = SimpleBot.choose(game, 1, memory)
      next = Player.move(game.players[1], turn)
      assert Arena.contains?(game.arena, next.position)
      refute Board.has?(game.occupied, next.position)
    end
  end

  test "decision work does not grow with the trail map" do
    sparse = game()
    occupied = for x <- 0..99, y <- 0..99, x > 10 and y > 10, into: %{}, do: {{x, y}, 2}
    dense = %{sparse | occupied: Map.merge(occupied, sparse.occupied)}
    memory = SimpleBot.init(1, :pro)
    assert reductions(dense, memory) <= reductions(sparse, memory) + 300
  end

  test "optimized decisions preserve the recorded seeded four-goat replays" do
    fixtures = [
      {{24, 14}, 1, "e141a9951cbbebdd77502ce25698697ba5c3c07ed770be6bc7fb3a42dede5c56"},
      {{24, 14}, 7, "31b868b4dae94a34ec3f7648f74cb31dc7dc5e30d8017a90835ba22ae7210945"},
      {{24, 14}, 31, "f5fa28b020b19916a527b3feacd431a8b4a53de2e3cbf1ad3ed2cb59158c6a7d"},
      {{24, 14}, 99, "17e4913afdc44672fff4121f86184353093ebf9a5a75fc828042825577dfc925"},
      {{39, 23}, 1, "0a9e1118f044c8c7793f8a1bfb3e2e36674ef4ab117dfa0e64d825e7f64cbc7a"},
      {{39, 23}, 7, "7fd8f4c3bee9f328d1d8ee53a190e9eac1909a79924f33e25d01024c2c37827e"},
      {{39, 23}, 31, "2edc94067872cde9d39c2bb2d4567b1e33b9e59dd839922a75af2cb8cd2b14b1"},
      {{39, 23}, 99, "04320ae40acec2f4c2aa882304c7227f525d1f7427fd91dccfc9d1425c67c950"},
      {{51, 30}, 1, "bbc65986d62958d38d2547dafc318f1e1774af259301e30176ca852ad7daa4ca"},
      {{51, 30}, 7, "ecfaf5f809d6df66c64917d409e98806e77073f835c8b11374852726dd401d59"},
      {{51, 30}, 31, "fb73663f20e7d632804f650e4b61c3afd213114050261016ee3f20b39b66d48d"},
      {{51, 30}, 99, "10347838617a7ff35c54862ef3fecf61896380375c7062fda38f4347c4149dd2"},
      {{78, 46}, 1, "3c0d716957360f1d05c16d92bfcce907458c499a335fe0568d8565e5fa260efd"},
      {{78, 46}, 7, "5ddd05ef6b8b8021ae0a201a01f0cf50cd1678e4b71341cf11ce63aa34f7cdb2"},
      {{78, 46}, 31, "f44f8ffaa11d9f4ddf5f2416cdf5d2333387c03b2b70f6deb5615d2047a4bf41"},
      {{78, 46}, 99, "3ba70ef567778575c1702d8df6d36c71fb3a301829220907605518c84c056ef3"}
    ]

    for {{width, height}, seed, expected} <- fixtures do
      match =
        Badge.App.Goatwars.Page.init(
          countdown_ms: 0,
          seed: seed,
          rules: %{width: width, height: height, explosion_radius: 2, retract_speed: 8}
        ).match

      match = Badge.App.Goatwars.Match.run(%{match | record_replay: true}, 5000)

      digest =
        :crypto.hash(:sha256, :erlang.term_to_binary({match.game.status, match.game.tick, match.replay})) |> Base.encode16(case: :lower)

      assert digest == expected
    end
  end

  defp game do
    {:ok, game} =
      Game.new(%{width: 100, height: 100, shrink_after: :never}, [
        %{id: 1, position: {4, 4}, direction: :east},
        %{id: 2, position: {8, 8}, direction: :west}
      ])

    game
  end

  defp reductions(game, memory) do
    {:reductions, before} = Process.info(self(), :reductions)
    SimpleBot.choose(game, 1, memory)
    {:reductions, after_count} = Process.info(self(), :reductions)
    after_count - before
  end
end
