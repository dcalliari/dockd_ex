defmodule DockdWeb.PlannerController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Dockd.Accounts
  alias Dockd.Planner

  operation(:show,
    summary: "Show planner summary",
    responses: %{200 => {"Planner", "application/json", DockdWeb.ApiSchemas.Error}}
  )

  def show(conn, _params) do
    summary = Planner.summary(Accounts.default_owner())

    json(conn, %{
      money: summary.money,
      recommendation: recommendation_payload(summary.recommendation),
      calendar_empty_reason: summary.calendar_empty_reason,
      opportunities: Enum.map(summary.opportunities, &opportunity_payload/1),
      calendar:
        Enum.map(summary.calendar, fn item ->
          %{
            game_id: item.game.id,
            title: item.game.title,
            release_id: item.release.id,
            release_date: item.release.release_date,
            recommendation: item.recommendation,
            reserved_cents: item.reserved_cents
          }
        end),
      backlog:
        Enum.map(summary.backlog, fn item ->
          %{
            game_id: item.game.id,
            title: item.game.title,
            oldest_at: item.oldest_at,
            recommendation: %{
              reason: item.recommendation.reason,
              confidence: item.recommendation.confidence
            }
          }
        end)
    })
  end

  defp opportunity_payload(item) do
    %{
      game_id: item.game.id,
      title: item.game.title,
      release_id: item.release.id,
      release_date: item.release.release_date,
      target_price_cents: item.entry.target_price_cents,
      currency: item.entry.currency,
      verdict: item.verdict,
      verdict_label: item.verdict_label,
      verdict_reason: item.verdict_reason,
      observation:
        if item.observation do
          %{
            price_cents: item.observation.price_cents,
            currency: item.observation.currency,
            observed_at: item.observation.observed_at,
            source: item.observation.source,
            stale: item.observation_stale?
          }
        end
    }
  end

  defp recommendation_payload(nil), do: nil

  defp recommendation_payload(recommendation) do
    %{
      game_id: recommendation.game.id,
      title: recommendation.game.title,
      reason: recommendation.reason,
      confidence: recommendation.confidence
    }
  end
end
