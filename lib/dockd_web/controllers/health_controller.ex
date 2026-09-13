defmodule DockdWeb.HealthController do
  use DockdWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
