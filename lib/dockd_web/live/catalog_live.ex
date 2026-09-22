defmodule DockdWeb.CatalogLive do
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Catalog
  alias Dockd.Library
  alias Dockd.Library.Entry

  @impl true
  def mount(params, _session, socket) do
    {:ok, load(socket, params)}
  end

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, load(socket, params)}

  @impl true
  def handle_event("search", params, socket) do
    search = Map.get(params, "search", Map.get(params, "catalog", %{}) |> Map.get("search", ""))
    {:noreply, load(socket, %{"search" => search})}
  end

  def handle_event("add_to_library", %{"id" => id}, socket) do
    user = Accounts.default_owner()

    result =
      case Library.get_entry_for_game(user, id) do
        nil -> Library.create_entry(user, %{game_id: id, purchase_intent: :want})
        entry -> Library.update_entry(user, entry, %{purchase_intent: :want})
      end

    case result do
      {:ok, _entry} -> {:noreply, load(socket, socket.assigns.params)}
      {:error, _changeset} -> {:noreply, load(socket, socket.assigns.params)}
    end
  end

  defp load(socket, params) do
    user = Accounts.default_owner()
    search = params |> Map.get("search", "") |> to_string() |> String.trim()
    games = Catalog.list_games()
    entries = Library.list_entries(user)

    filtered_games =
      Enum.filter(games, fn game ->
        search == "" or String.contains?(String.downcase(game.title), String.downcase(search))
      end)

    assign(socket,
      page_title: "Descobrir",
      games: filtered_games,
      entries_by_game: Map.new(entries, &{&1.game_id, &1}),
      search: search,
      params: %{"search" => search},
      search_form: to_form(%{"search" => search}, as: :catalog)
    )
  end

  defp platform_label(%{releases: releases}) do
    releases
    |> Enum.map(&enum_label(&1.platform))
    |> Enum.uniq()
    |> Enum.join(" · ")
  end

  defp relation_label(game, entries_by_game) do
    case Map.get(entries_by_game, game.id) do
      %Entry{purchase_intent: intent} when intent in [:want, :planned, :preordered] -> "Na lista"
      _ -> nil
    end
  end
end
