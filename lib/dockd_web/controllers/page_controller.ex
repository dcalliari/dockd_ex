defmodule DockdWeb.PageController do
  use DockdWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
