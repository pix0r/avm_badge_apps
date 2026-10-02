defmodule Badge.App.Goatwars.SimpleBotTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.{Arena, Board, Game, Player, SimpleBot}

  test "controller memory keeps only the small policy needed on every frame" do
    for profile <- [:beginner, :intermediate, :expert, :pro] do
      memory = SimpleBot.init(1, profile)
      assert :erts_debug.flat_size(memory) <= 16
      {_, next} = SimpleBot.choose(game(), 1, memory)
      assert :erts_debug.flat_size(next) <= 16
    end
  end

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

  test "cruises to the last clear cell without idle turns or distant chasing" do
    game = game()
    game = %{game | players: Map.put(game.players, 2, %{game.players[2] | position: {99, 99}})}

    for x <- [4, 40, 96, 97, 98], seed <- 1..64 do
      player = %{game.players[1] | position: {x, 4}}
      state = %{game | players: Map.put(game.players, 1, player), occupied: %{{x, 4} => 1, {99, 99} => 2}}
      assert {nil, _} = SimpleBot.choose(state, 1, SimpleBot.init(seed, :pro))
    end
  end

  test "when blocked chooses the longer clear lane beyond the local escape check" do
    {:ok, game} =
      Game.new(%{width: 21, height: 21, shrink_after: :never}, [
        %{id: 1, position: {10, 10}, direction: :east},
        %{id: 2, position: {20, 20}, direction: :west}
      ])

    game = %{game | players: Map.put(game.players, 2, %{game.players[2] | alive: false})}

    for {obstacle, expected} <- [{{10, 6}, :right}, {{10, 14}, :left}], seed <- 1..64 do
      state = %{game | occupied: %{{10, 10} => 1, {11, 10} => 2, obstacle => 2}}
      assert {^expected, _} = SimpleBot.choose(state, 1, SimpleBot.init(seed))
      assert {^expected, _} = SimpleBot.choose(Game.compact(state), 1, SimpleBot.init(seed))
    end
  end

  test "safety turns choose the longer lane even when the forward cell is empty" do
    {:ok, game} =
      Game.new(%{width: 21, height: 21, shrink_after: :never}, [
        %{id: 1, position: {10, 10}, direction: :east},
        %{id: 2, position: {12, 10}, direction: :west}
      ])

    for reason <- [:head_on, :dead_end], seed <- 1..64 do
      occupied = Map.put(game.occupied, {10, 6}, 2)
      players = if reason == :dead_end, do: Map.put(game.players, 2, %{game.players[2] | alive: false}), else: game.players
      occupied = if reason == :dead_end, do: Map.merge(occupied, %{{11, 9} => 2, {11, 11} => 2}), else: occupied
      state = %{game | players: players, occupied: occupied}
      refute Board.has?(state.occupied, {11, 10})
      assert {:right, _} = SimpleBot.choose(state, 1, SimpleBot.init(seed))
    end
  end

  test "equal turning lanes use reproducible seeded tie breaking" do
    {:ok, game} =
      Game.new(%{width: 21, height: 21, shrink_after: :never}, [
        %{id: 1, position: {10, 10}, direction: :east},
        %{id: 2, position: {20, 20}, direction: :west}
      ])

    game = %{game | players: Map.put(game.players, 2, %{game.players[2] | alive: false}), occupied: %{{10, 10} => 1, {11, 10} => 2}}

    turns =
      for seed <- 1..64 do
        memory = SimpleBot.init(seed, aggression: 0)
        decision = SimpleBot.choose(game, 1, memory)
        assert decision == SimpleBot.choose(game, 1, memory)
        elem(decision, 0)
      end

    assert MapSet.new(turns) == MapSet.new([:left, :right])
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

  test "a blocked XL wide decision scans lanes within a bounded work budget" do
    {:ok, game} =
      Game.new(%{width: 78, height: 46, shrink_after: :never}, [
        %{id: 1, position: {39, 23}, direction: :north},
        %{id: 2, position: {77, 45}, direction: :west}
      ])

    game =
      Game.compact(%{
        game
        | players: Map.put(game.players, 2, %{game.players[2] | alive: false}),
          occupied: %{{39, 23} => 1, {39, 22} => 2}
      })

    for seed <- 1..32 do
      memory = SimpleBot.init(seed)
      assert {:left, _} = SimpleBot.choose(game, 1, memory)
      assert reductions(game, memory) <= 1800
    end
  end

  test "space-cruising decisions preserve recorded seeded four-goat replays" do
    fixtures = [
      {{24, 14}, 1, "5505a08cf4c4af550e5714cd096afa8d4b0c9e331daceca2a35f6c6fa3e22636"},
      {{24, 14}, 7, "5505a08cf4c4af550e5714cd096afa8d4b0c9e331daceca2a35f6c6fa3e22636"},
      {{24, 14}, 31, "5505a08cf4c4af550e5714cd096afa8d4b0c9e331daceca2a35f6c6fa3e22636"},
      {{24, 14}, 99, "5505a08cf4c4af550e5714cd096afa8d4b0c9e331daceca2a35f6c6fa3e22636"},
      {{39, 23}, 1, "120ef155469b13216767435fef4f8b1909f5c1ea654a6f407d207b0187290f7b"},
      {{39, 23}, 7, "474e49f23a72c8ba28754487a800c0540118e41dae7fc1a7ecc716297c37bbca"},
      {{39, 23}, 31, "19978f29dbc33e1fac4d07bf424d88cfd4ea4f6deb1b68e228b905aacac95edc"},
      {{39, 23}, 99, "474e49f23a72c8ba28754487a800c0540118e41dae7fc1a7ecc716297c37bbca"},
      {{51, 30}, 1, "bb7b0b8ae6b7711b284c28ff8da65aa32d7354ef84d8040a10f55778d8ad240b"},
      {{51, 30}, 7, "a1a764aaee05cfe9bbcde42a8df7375e6bb2bd434d53425045c011cf39e7c901"},
      {{51, 30}, 31, "a1a764aaee05cfe9bbcde42a8df7375e6bb2bd434d53425045c011cf39e7c901"},
      {{51, 30}, 99, "a1a764aaee05cfe9bbcde42a8df7375e6bb2bd434d53425045c011cf39e7c901"},
      {{78, 46}, 1, "81bc68e61968274bbc3aa2e7676a44a1b754ac21d8d33b9a6026578d03aa6067"},
      {{78, 46}, 7, "81bc68e61968274bbc3aa2e7676a44a1b754ac21d8d33b9a6026578d03aa6067"},
      {{78, 46}, 31, "81bc68e61968274bbc3aa2e7676a44a1b754ac21d8d33b9a6026578d03aa6067"},
      {{78, 46}, 99, "81bc68e61968274bbc3aa2e7676a44a1b754ac21d8d33b9a6026578d03aa6067"}
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
