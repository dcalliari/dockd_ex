defmodule DockdWeb.LibraryLive do
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Catalog
  alias Dockd.Library
  alias Dockd.Library.Entry

  @impl true
  def mount(params, _session, socket) do
    user = Accounts.default_owner()
    {:ok, load(socket, user, params)}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, load(socket, socket.assigns.user, params)}

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.merge(socket.assigns.filters, normalize_params(params))
    {:noreply, load(socket, socket.assigns.user, filters)}
  end

  def handle_event("new_entry", %{"game_id" => game_id}, socket) do
    case Library.create_entry(socket.assigns.user, %{game_id: game_id}) do
      {:ok, _entry} ->
        {:noreply,
         load(socket, socket.assigns.user, socket.assigns.filters)
         |> put_flash(:info, "Jogo adicionado à biblioteca.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("edit_entry", %{"id" => id}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)
    {:noreply, assign(socket, editing: entry, form: to_form(Entry.changeset(entry, %{})))}
  end

  def handle_event("close_editor", _params, socket), do: {:noreply, assign(socket, editing: nil)}

  def handle_event("quick_state", %{"id" => id, "play_state" => state}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)

    case Library.update_entry(socket.assigns.user, entry, %{play_state: state}) do
      {:ok, _entry} -> {:noreply, load(socket, socket.assigns.user, socket.assigns.filters)}
      {:error, changeset} -> {:noreply, put_flash(socket, :error, inspect(changeset.errors))}
    end
  end

  def handle_event("save_entry", %{"entry" => attrs}, socket) do
    entry = socket.assigns.editing

    case Library.update_entry(socket.assigns.user, entry, attrs) do
      {:ok, _entry} ->
        {:noreply,
         load(socket, socket.assigns.user, socket.assigns.filters)
         |> put_flash(:info, "Entrada atualizada.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("remove_ownership", %{"id" => id}, socket) do
    ownership = Library.get_ownership!(socket.assigns.user, id)

    case Library.delete_ownership(socket.assigns.user, ownership) do
      {:ok, _} -> {:noreply, load(socket, socket.assigns.user, socket.assigns.filters)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Não foi possível remover: #{inspect(reason)}")}
    end
  end

  def handle_event("remove_entry", %{"id" => id}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)

    case Library.delete_entry(socket.assigns.user, entry) do
      {:ok, _} ->
        {:noreply,
         load(socket, socket.assigns.user, socket.assigns.filters)
         |> put_flash(:info, "Entrada removida.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover: #{inspect(reason)}")}
    end
  end

  defp load(socket, user, params) do
    filters = normalize_params(params)
    all_entries = Library.list_entries(user)
    ownerships = Library.list_ownerships(user)
    owned_game_ids = ownerships |> Enum.map(& &1.release.game_id) |> MapSet.new()
    entries = filter_entries(all_entries, filters, owned_game_ids)
    games = Catalog.list_games()
    entry_game_ids = MapSet.new(all_entries, & &1.game_id)
    counts = counts(all_entries, owned_game_ids)

    assign(socket,
      page_title: "Biblioteca",
      user: user,
      entries: entries,
      all_entries: all_entries,
      ownerships: ownerships,
      orphan_ownerships: Enum.reject(ownerships, &MapSet.member?(entry_game_ids, &1.release.game_id)),
      ownerships_by_game: Enum.group_by(ownerships, & &1.release.game_id),
      owned_game_ids: owned_game_ids,
      games: games,
      editing: nil,
      form: to_form(Entry.changeset(%Entry{}, %{})),
      filters: filters,
      counts: counts,
      tab_counts: Map.put(counts, :all, counts.collection)
    )
  end

  defp normalize_params(params) do
    nested = Map.get(params, "filters", %{})
    params = Map.merge(Map.drop(params, ["filters"]), nested)
    Map.put_new(params, "tab", "all")
  end

  defp filter_entries(entries, filters, owned_game_ids) do
    search = filters |> Map.get("search", "") |> to_string() |> String.downcase()

    Enum.filter(entries, fn entry ->
      matches_search = search == "" or String.contains?(String.downcase(entry.game.title), search)

      matches_tab =
        case Map.get(filters, "tab") do
          "playing" -> entry.play_state == :playing
          "backlog" -> entry.backlog == :backlog
          "want" -> entry.purchase_intent in [:want, :planned, :preordered]
          "all" -> MapSet.member?(owned_game_ids, entry.game_id)
          "finished" -> entry.play_state == :finished
          _ -> true
        end

      matches_search and matches_tab
    end)
  end

  defp counts(entries, owned_game_ids) do
    %{
      playing: Enum.count(entries, &(&1.play_state == :playing)),
      backlog: Enum.count(entries, &(&1.backlog == :backlog)),
      want: Enum.count(entries, &(&1.purchase_intent in [:want, :planned, :preordered])),
      collection: MapSet.size(owned_game_ids),
      finished: Enum.count(entries, &(&1.play_state == :finished))
    }
  end

  defp status_label(%{play_state: :playing}), do: "Jogando"
  defp status_label(%{play_state: :finished}), do: "Terminado"
  defp status_label(%{play_state: :abandoned}), do: "Abandonado"
  defp status_label(%{backlog: :backlog}), do: "Backlog"
  defp status_label(_), do: nil

  defp platform_label(%{releases: [%{platform: platform} | _]}), do: enum_label(platform)
  defp platform_label(_), do: nil

  defp ownership_label(ownerships_by_game, game_id) do
    ownerships_by_game
    |> Map.get(game_id, [])
    |> List.first()
    |> case do
      nil -> nil
      ownership -> enum_label(ownership.ownership_type)
    end
  end
end
