defmodule DockdWeb.PlannerLive do
  use DockdWeb, :live_view
  alias Dockd.Accounts
  alias Dockd.Planner
  @impl true
  def mount(_params, _session, socket) do
    owner = Accounts.default_owner()
    {:ok, assign(socket, owner: owner, summary: Planner.summary(owner))}
  end
end
