defmodule Badge.App.Goatwars.StartupTest do
  use ExUnit.Case, async: true
  alias Badge.App.Goatwars.Page

  test "opening responds before decoding artwork or building the match" do
    {:reductions, before} = :erlang.process_info(self(), :reductions)
    loading = Page.init()
    {:reductions, after_init} = :erlang.process_info(self(), :reductions)

    assert loading.screen == :loading
    refute Map.has_key?(loading, :art)
    refute Map.has_key?(loading, :match)
    assert after_init - before < 1000
    assert Page.refresh(loading) == 0
    assert Page.tick_interval(loading) == 100
    assert Enum.any?(Page.render(loading), &match?({:text, _, _, _, _, _, "Loading GoatWars..."}, &1))
  end

  test "tick before render leaves a loading frame before the title is prepared" do
    first_frame = Page.init() |> Page.advance(0)
    assert first_frame.screen == :loading
    refute Map.has_key?(first_frame, :art)
    assert Enum.any?(Page.render(first_frame), &match?({:text, _, _, _, _, _, "Loading GoatWars..."}, &1))

    title = Page.advance(first_frame, 100)
    assert title.screen == :title
    assert title.match.game.tick == 0
    assert title.launch_remaining == 3000
    assert Page.advance(title, 10_000) == title
    assert Enum.any?(Page.render(title), &match?({:text, _, _, _, _, _, "Enter: play"}, &1))
  end

  test "deferred initialization preserves options and ignores keys until ready" do
    loading = Page.init(rules: %{width: 24, height: 14}, profiles: %{1 => :human}, seed: 42, countdown_ms: 1500)
    assert loading.screen == :loading
    for key <- [:enter, {:char, ?s}, {:move, :left}, {:nav, :home}], do: assert(Page.handle_key(key, loading) == :ignore)
    title = loading |> Page.advance(0) |> Page.advance(100)
    assert title.match.game.config.width == 24
    assert title.match.game.config.height == 14
    assert title.match.controllers[1] == :human
    assert title.launch_remaining == 1500
    {:ok, countdown} = Page.handle_key(:enter, title)
    assert Page.advance(countdown, 1000).match.game.tick == 0
    assert Page.advance(Page.advance(countdown, 1000), 2500).started
  end
end
