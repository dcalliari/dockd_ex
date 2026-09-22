defmodule DockdWeb.GameLive do
  use DockdWeb, :live_view

  alias Dockd.{Accounts, Catalog, Library}

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    game = Catalog.get_game!(id)
    user = Accounts.default_owner()
    return_context = return_context(Map.get(params, "from"))

    {:ok,
     assign(socket,
       page_title: game.title,
       game: game,
       user: user,
       entry: Library.get_entry_for_game(user, game.id),
       return_to: return_context.path,
       return_label: return_context.label
     )}
  end

  @impl true
  def handle_event("add_to_list", _params, socket) do
    result =
      case socket.assigns.entry do
        nil ->
          Library.create_entry(socket.assigns.user, %{
            game_id: socket.assigns.game.id,
            purchase_intent: :want
          })

        entry ->
          Library.update_entry(socket.assigns.user, entry, %{purchase_intent: :want})
      end

    case result do
      {:ok, entry} -> {:noreply, assign(socket, entry: entry)}
      {:error, changeset} -> {:noreply, put_flash(socket, :error, error_message(changeset))}
    end
  end

  def handle_event("remove_from_list", _params, socket) do
    case Library.update_entry(socket.assigns.user, socket.assigns.entry, %{purchase_intent: :none}) do
      {:ok, entry} -> {:noreply, assign(socket, entry: entry)}
      {:error, changeset} -> {:noreply, put_flash(socket, :error, error_message(changeset))}
    end
  end

  defp return_context("list"), do: %{path: "/", label: "Lista"}
  defp return_context("catalog"), do: %{path: "/catalogo", label: "Descobrir"}
  defp return_context(_), do: %{path: "/catalogo", label: "Descobrir"}

  defp relation?(nil), do: false

  defp relation?(%{purchase_intent: intent}),
    do: intent in [:want, :planned, :preordered]

  defp platform_label(%{releases: releases}) do
    releases
    |> Enum.map(&enum_label(&1.platform))
    |> Enum.uniq()
    |> Enum.join(" · ")
  end

  defp release_date_label(%{release_date: nil}), do: "a definir"
  defp release_date_label(%{release_date_precision: :tbd}), do: "a definir"

  defp release_date_label(%{release_date_precision: :year, release_date: date}),
    do: "#{date.year}"

  defp release_date_label(%{release_date_precision: :month, release_date: date}) do
    "#{month_label(date.month)} #{date.year}"
  end

  defp release_date_label(%{release_date_precision: :quarter, release_date: date}) do
    "T#{div(date.month - 1, 3) + 1} #{date.year}"
  end

  defp release_date_label(%{release_date: date}), do: date_pt_br(date)

  defp month_label(1), do: "jan"
  defp month_label(2), do: "fev"
  defp month_label(3), do: "mar"
  defp month_label(4), do: "abr"
  defp month_label(5), do: "mai"
  defp month_label(6), do: "jun"
  defp month_label(7), do: "jul"
  defp month_label(8), do: "ago"
  defp month_label(9), do: "set"
  defp month_label(10), do: "out"
  defp month_label(11), do: "nov"
  defp month_label(12), do: "dez"

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
