defmodule DockdWeb.PageController do
  use DockdWeb, :controller

  def home(conn, _params), do: redirect(conn, to: "/catalogo")
end
