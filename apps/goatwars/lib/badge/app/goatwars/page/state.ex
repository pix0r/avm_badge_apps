defmodule Badge.App.Goatwars.Page.State do
  @moduledoc "Badge shell timing, player setup, scores and effects."
  def new(%{match: _, layout: _, setup: _} = fields) do
    Map.merge(
      %{
        draft: nil,
        settings_from: :game,
        compact: true,
        benchmark: false,
        bench_previous: nil,
        input_ref: :erlang.make_ref(),
        result_until: nil,
        launch_at: nil,
        round: 1,
        scores: %{},
        paused: false,
        due_at: nil,
        frame: 0,
        started: false,
        launch_remaining: 3000,
        screen: :game,
        selected: 1,
        effects: []
      },
      fields
    )
  end
end
