defmodule DockdWeb.CatalogLive do
  use DockdWeb, :live_view
  alias Dockd.Accounts
  alias Dockd.Catalog
  alias Dockd.Catalog.{Game, Release}
  alias Dockd.Library

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       games: Catalog.list_games(),
       game: nil,
       game_form: game_form(%Game{}),
       release_form: release_form(%Release{})
     )}
  end

  @impl true
  def handle_event("add_to_library", %{"id" => id}, socket) do
    case Library.create_entry(Accounts.default_owner(), %{game_id: id}) do
      {:ok, _entry} -> {:noreply, put_flash(socket, :info, "Jogo adicionado à biblioteca.")}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Jogo já está na biblioteca.")}
    end
  end

  def handle_event("new_game", _, socket),
    do: {:noreply, assign(socket, game: nil, game_form: game_form(%Game{}))}

  def handle_event("edit_game", %{"id" => id}, socket) do
    game = Catalog.get_game!(id)
    {:noreply, assign(socket, game: game, game_form: game_form(game))}
  end

  def handle_event("save_game", %{"game" => attrs}, socket) do
    attrs = normalize_platforms(attrs)

    result =
      if socket.assigns.game,
        do: Catalog.update_game(socket.assigns.game, attrs),
        else: Catalog.create_game(attrs)

    case result do
      {:ok, game} ->
        {:noreply,
         socket
         |> assign(
           games: Catalog.list_games(),
           game: game,
           game_form: game_form(game),
           release_form: release_form(%Release{})
         )
         |> put_flash(:info, "Obra salva.")}

      {:error, changeset} ->
        {:noreply, assign(socket, game_form: to_form(changeset))}
    end
  end

  def handle_event("edit_release", %{"id" => id, "game-id" => game_id}, socket) do
    release = Catalog.get_release!(game_id, id)

    {:noreply,
     assign(socket, game: Catalog.get_game!(game_id), release_form: release_form(release))}
  end

  def handle_event("save_release", %{"release" => attrs}, socket) do
    game = socket.assigns.game

    result =
      if attrs["id"] in [nil, ""],
        do: Catalog.create_release(game.id, attrs),
        else: Catalog.update_release(Catalog.get_release!(game.id, attrs["id"]), attrs)

    case result do
      {:ok, _release} ->
        {:noreply,
         assign(socket,
           games: Catalog.list_games(),
           game: Catalog.get_game!(game.id),
           release_form: release_form(%Release{})
         )
         |> put_flash(:info, "Versao salva.")}

      {:error, changeset} ->
        {:noreply, assign(socket, release_form: to_form(changeset))}
    end
  end

  defp game_form(game), do: game |> Game.changeset(%{}) |> to_form()
  defp release_form(release), do: release |> Release.changeset(%{}) |> to_form()

  defp normalize_platforms(attrs) do
    Map.update(attrs, "other_platforms", [], fn value ->
      value |> to_string() |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end)
  end
end
