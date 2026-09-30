defmodule Badge.App.Goatwars.BudgetTest do
  use ExUnit.Case, async: false
  alias Badge.App.Goatwars.{Bot, Match}

  test "AI stops exploring space once additional cells cannot change its score" do
    {seen, profile} = calls(:reachable)
    assert seen != []
    assert Enum.max(seen) <= min(profile.safe_room, profile.search_limit)
  end

  test "AI stops looking down a clear runway after score and safety are decided" do
    {seen, profile} = calls(:runway)
    assert seen != []
    limit = max(profile.runway_limit, profile.reaction_ticks - profile.decision_delay - 1)
    assert Enum.max(seen) <= limit
  end

  test "all difficulty presets preserve the original command replays and results" do
    {fixtures, _} = Code.eval_file(Path.expand("../../../fixtures/goatwars-replays.exs", __DIR__))

    for {level, seed, ticks, status, totals, digest} <- fixtures do
      match =
        Match.demo(%{width: 78, height: 46, explosion_radius: 2, retract_speed: 8}, seed, %{
          1 => level,
          2 => level,
          3 => level,
          4 => level
        })
        |> Match.run(3000)

      assert match.game.tick == ticks
      assert match.game.status == status
      assert match.totals == totals
      assert :erlang.md5(:erlang.term_to_binary(match.replay)) == digest
    end
  end

  defp calls(function) do
    parent = self()
    memory = Bot.init(1, :pro)
    match = Match.demo(%{width: 78, height: 46})
    arity = :_
    :erlang.trace_pattern({Bot, function, arity}, true, [:local])
    on_exit(fn -> :erlang.trace_pattern({Bot, function, arity}, false, [:local]) end)

    pid =
      spawn(fn ->
        receive do
          :go -> Bot.choose(match.game, 1, memory)
        end

        send(parent, :done)
        receive do: (:stop -> :ok)
      end)

    :erlang.trace(pid, true, [:call, {:tracer, self()}])
    send(pid, :go)
    assert_receive :done, 5000
    ref = :erlang.trace_delivered(pid)
    assert_receive {:trace_delivered, ^pid, ^ref}, 1000
    send(pid, :stop)
    {collect(pid, function, []), memory.profile}
  end

  defp collect(pid, function, acc) do
    receive do
      {:trace, ^pid, :call, {Bot, ^function, args}} ->
        collect(pid, function, [Enum.at(args, 4) | acc])
    after
      0 -> acc
    end
  end
end
