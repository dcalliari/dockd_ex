defmodule DockdWeb.CatalogLive do
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Catalog
  alias Dockd.Library

  @impl true
  def mount(_params, _session, socket) do
    user = Accounts.default_owner()
    library_game_ids = user |> Library.list_entries() |> MapSet.new(& &1.game_id)

    {:ok,
     assign(socket,
       page_title: "Catálogo",
       games: Catalog.list_games(),
       library_game_ids: library_game_ids
     )}
  end

  @impl true
  def handle_event("add_to_library", %{"id" => id}, socket) do
    case Library.create_entry(Accounts.default_owner(), %{game_id: id}) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> assign(:library_game_ids, MapSet.put(socket.assigns.library_game_ids, id))
         |> put_flash(:info, "Jogo adicionado à biblioteca.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Jogo já está na biblioteca.")}
    end
  end
end
