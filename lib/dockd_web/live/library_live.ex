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
    filters = Map.take(params, ["search", "backlog", "play_state"])
    entries = Library.list_entries(user, filters)
    games = Catalog.list_games()

    assign(socket,
      user: user,
      entries: entries,
      ownerships: Library.list_ownerships(user),
      games: games,
      editing: nil,
      form: to_form(Entry.changeset(%Entry{}, %{})),
      filters: filters,
      groups: Enum.group_by(entries, &group_for/1)
    )
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
