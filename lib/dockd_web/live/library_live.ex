defmodule DockdWeb.LibraryLive do
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Library

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

  def handle_event("remove_from_list", %{"id" => id}, socket) do
    entry = Library.get_entry!(socket.assigns.user, id)

    case Library.update_entry(socket.assigns.user, entry, %{purchase_intent: :none}) do
      {:ok, _entry} -> {:noreply, load(socket, socket.assigns.user, socket.assigns.filters)}
      {:error, changeset} -> {:noreply, put_flash(socket, :error, error_message(changeset))}
    end
  end

  defp load(socket, user, params) do
    search = params |> Map.get("search", "") |> to_string() |> String.trim()

    entries =
      user
      |> Library.list_entries()
      |> Enum.filter(&(&1.purchase_intent in [:want, :planned, :preordered]))
      |> Enum.filter(fn entry ->
        search == "" or
          String.contains?(String.downcase(entry.game.title), String.downcase(search))
      end)

    assign(socket,
      page_title: "Lista",
      user: user,
      entries: entries,
      filters: %{"search" => search},
      search: search,
      search_form: to_form(%{"search" => search}, as: :list)
    )
  end

  defp platform_label(%{releases: releases}) do
    releases
    |> Enum.map(&enum_label(&1.platform))
    |> Enum.uniq()
    |> Enum.join(" · ")
  end

  defp error_message(changeset) do
    changeset.errors
    |> Keyword.values()
    |> List.first()
    |> case do
      {message, _} -> message
      _ -> "Não foi possível atualizar a lista."
    end
  end
end
