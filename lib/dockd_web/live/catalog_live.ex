defmodule DockdWeb.CatalogLive do
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Catalog
  alias Dockd.Library

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Catálogo", games: Catalog.list_games())}
  end

  @impl true
  def handle_event("add_to_library", %{"id" => id}, socket) do
    case Library.create_entry(Accounts.default_owner(), %{game_id: id}) do
      {:ok, _entry} -> {:noreply, put_flash(socket, :info, "Jogo adicionado à biblioteca.")}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Jogo já está na biblioteca.")}
    end
  end
end
