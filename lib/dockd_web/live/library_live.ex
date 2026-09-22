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
  def handle_event("filter", params, socket),
    do: {:noreply, load(socket, socket.assigns.user, params)}

  def handle_event("new_entry", %{"game_id" => game_id}, socket) do
    case Library.create_entry(socket.assigns.user, %{game_id: game_id}) do
      {:ok, _entry} ->
        {:noreply,
         load(socket, socket.assigns.user, %{})
         |> put_flash(:info, "Jogo adicionado à biblioteca.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("toggle_state_menu", %{"id" => id}, socket) do
    state_menu_id = if socket.assigns.state_menu_id == id, do: nil, else: id
    {:noreply, assign(socket, :state_menu_id, state_menu_id)}
  end

  def handle_event("set_state", %{"id" => id, "state" => state}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)

    case state_attrs(state) do
      nil ->
        {:noreply, socket}

      attrs ->
        case Library.update_entry(socket.assigns.user, entry, attrs) do
          {:ok, _entry} -> {:noreply, load(socket, socket.assigns.user, socket.assigns.filters)}
          {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
        end
    end
  end

  def handle_event("edit_entry", %{"id" => id}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)
    {:noreply, assign(socket, editing: entry, form: to_form(Entry.changeset(entry, %{})))}
  end

  def handle_event("save_entry", %{"entry" => attrs}, socket) do
    entry = socket.assigns.editing

    case Library.update_entry(socket.assigns.user, entry, attrs) do
      {:ok, updated} ->
        socket = load(socket, socket.assigns.user, socket.assigns.filters)

        {:noreply,
         assign(socket,
           editing: updated,
           form: to_form(Entry.changeset(updated, %{}))
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("remove_ownership", %{"id" => id}, socket) do
    ownership = Library.get_ownership!(socket.assigns.user, id)

    case Library.delete_ownership(socket.assigns.user, ownership) do
      {:ok, _} ->
        {:noreply, load(socket, socket.assigns.user, socket.assigns.filters)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover: #{inspect(reason)}")}
    end
  end

  def handle_event("remove_entry", %{"id" => id}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)

    case Library.delete_entry(socket.assigns.user, entry) do
      {:ok, _} ->
        {:noreply, load(socket, socket.assigns.user, socket.assigns.filters)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover: #{inspect(reason)}")}
    end
  end

  defp load(socket, user, params) do
    all_entries = Library.list_entries(user)
    ownerships = Library.list_ownerships(user)
    owned_game_ids = MapSet.new(ownerships, & &1.release.game_id)

    filters =
      params
      |> Map.take(["search", "backlog", "play_state", "tab"])
      |> Map.put_new("tab", "all")

    entries =
      if filters["tab"] == "all" and MapSet.size(owned_game_ids) == 0 do
        all_entries
      else
        Library.list_entries(user, filters)
      end

    games = Catalog.list_games()

    assign(socket,
      page_title: "Biblioteca",
      user: user,
      entries: entries,
      ownerships: ownerships,
      owned_game_ids: owned_game_ids,
      games: games,
      editing: nil,
      form: to_form(Entry.changeset(%Entry{}, %{})),
      filters: filters,
      tab_counts: tab_counts(all_entries, owned_game_ids),
      state_menu_id: nil
    )
  end

  defp tab_counts(entries, owned_game_ids) do
    %{
      playing: Enum.count(entries, &(&1.play_state == :playing)),
      backlog: Enum.count(entries, &(&1.backlog == :backlog)),
      want: Enum.count(entries, &(&1.purchase_intent in [:want, :planned, :preordered])),
      all: Enum.count(entries, &(&1.game_id in owned_game_ids)),
      finished: Enum.count(entries, &(&1.play_state == :finished))
    }
  end

  defp state_attrs("playing"), do: %{play_state: :playing, backlog: :no}
  defp state_attrs("finished"), do: %{play_state: :finished, backlog: :no}
  defp state_attrs("abandoned"), do: %{play_state: :abandoned, backlog: :no}
  defp state_attrs("backlog"), do: %{play_state: :unplayed, backlog: :backlog}
  defp state_attrs(_), do: nil

  defp status_label(%{play_state: :playing}), do: "Jogando"
  defp status_label(%{play_state: :finished}), do: "Terminado"
  defp status_label(%{play_state: :abandoned}), do: "Abandonado"
  defp status_label(%{backlog: :backlog}), do: "Backlog"
  defp status_label(_), do: nil

  defp platform_label(%{releases: [%{platform: platform} | _]}), do: enum_label(platform)
  defp platform_label(_), do: nil

  defp ownership_label(game_id, ownerships) do
    case Enum.find(ownerships, &(&1.release.game_id == game_id)) do
      %{ownership_type: :physical} -> "Físico"
      %{ownership_type: :digital} -> "Digital"
      %{ownership_type: type} -> enum_label(type)
      nil -> "Na lista"
    end
  end
end
