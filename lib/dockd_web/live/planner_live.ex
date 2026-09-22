defmodule DockdWeb.PlannerLive do
  use DockdWeb, :live_view
  alias Dockd.Accounts
  alias Dockd.Planner
  @impl true
  def mount(_params, _session, socket) do
    owner = Accounts.default_owner()
    {:ok, assign(socket, page_title: "Planejador", owner: owner, summary: Planner.summary(owner))}
  end

  defp release_date_label(%{release_date: nil}), do: "Data não informada"

  defp release_date_label(%{release_date: date, release_date_precision: :day}),
    do: date_pt_br(date)

  defp release_date_label(%{release_date: date, release_date_precision: :month}),
    do: Calendar.strftime(date, "%m/%Y")

  defp release_date_label(%{release_date: date, release_date_precision: :quarter}) do
    quarter = div(date.month - 1, 3) + 1
    "#{quarter}º tri. de #{date.year}"
  end

  defp release_date_label(%{release_date: date, release_date_precision: :year}),
    do: Integer.to_string(date.year)

  defp release_date_label(%{release_date: date, release_date_precision: :tbd}),
    do: "#{date.year}, a definir"

  defp release_date_label(%{release_date: date}), do: Planner.release_date_label(date)

  defp recommendation_reason(reason) do
    short = reason |> String.split(". ", parts: 2) |> List.first() |> String.trim_trailing(".")
    short <> "."
  end
end
