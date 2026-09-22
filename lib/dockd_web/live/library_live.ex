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

  def handle_event("edit_entry", %{"id" => id}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)
    {:noreply, assign(socket, editing: entry, form: to_form(Entry.changeset(entry, %{})))}
  end

  def handle_event("save_entry", %{"entry" => attrs}, socket) do
    entry = socket.assigns.editing

    case Library.update_entry(socket.assigns.user, entry, attrs) do
      {:ok, _entry} ->
        {:noreply,
         load(socket, socket.assigns.user, %{}) |> put_flash(:info, "Entrada atualizada.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("remove_ownership", %{"id" => id}, socket) do
    ownership = Library.get_ownership!(socket.assigns.user, id)

    case Library.delete_ownership(socket.assigns.user, ownership) do
      {:ok, _} ->
        {:noreply, load(socket, socket.assigns.user, %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover: #{inspect(reason)}")}
    end
  end

  def handle_event("remove_entry", %{"id" => id}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)

    case Library.delete_entry(socket.assigns.user, entry) do
      {:ok, _} ->
        {:noreply,
         load(socket, socket.assigns.user, %{}) |> put_flash(:info, "Entrada removida.")}

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

    entry_filters = if Map.has_key?(params, "tab"), do: filters, else: Map.delete(filters, "tab")
    entries = Library.list_entries(user, entry_filters)
    games = Catalog.list_games()

    assign(socket,
      user: user,
      entries: entries,
      ownerships: ownerships,
      games: games,
      editing: nil,
      form: to_form(Entry.changeset(%Entry{}, %{})),
      filters: filters,
      tab_counts: tab_counts(all_entries, owned_game_ids),
      groups: Enum.group_by(entries, &group_for/1)
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

  defp group_for(%{play_state: :playing}), do: "Jogando"
  defp group_for(%{backlog: :backlog}), do: "Backlog"

  defp group_for(%{purchase_intent: intent}) when intent in [:want, :planned, :preordered],
    do: "Quero comprar"

  defp group_for(%{play_state: state}) when state in [:finished, :abandoned],
    do: "Terminados / abandonados"

  defp group_for(_), do: "Outros"

  defp status_label(%{play_state: :playing}), do: "Jogando"
  defp status_label(%{play_state: :finished}), do: "Terminado"
  defp status_label(%{play_state: :abandoned}), do: "Abandonado"
  defp status_label(%{backlog: :backlog}), do: "Backlog"
  defp status_label(_), do: nil

  defp platform_label(%{releases: [%{platform: platform} | _]}), do: enum_label(platform)
  defp platform_label(_), do: nil
end
