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
      calendar:
        Enum.map(summary.calendar, fn item ->
          %{
            game_id: item.game.id,
            title: item.game.title,
            release_id: item.release.id,
            release_date: item.release.release_date,
            recommendation: item.recommendation
          }
        end),
      backlog:
        Enum.map(summary.backlog, fn item ->
          %{game_id: item.game.id, title: item.game.title, oldest_at: item.oldest_at}
        end)
    })
  end
end
