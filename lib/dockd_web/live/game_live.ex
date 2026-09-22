defmodule DockdWeb.GameLive do
  use DockdWeb, :live_view

  alias Dockd.{Accounts, Catalog, Library, Purchasing}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.default_owner()
    game = Catalog.get_game!(id)
    {:ok, assign_game(socket, user, game)}
  end

  @impl true
  def handle_event(
        "save_observation",
        %{"release_id" => release_id, "observation" => attrs},
        socket
      ) do
    attrs =
      attrs
      |> normalize_datetime("observed_at")
      |> normalize_money("price_cents")
      |> Map.put("release_id", release_id)

    case Purchasing.create_price_observation(socket.assigns.user, attrs) do
      {:ok, _} ->
        {:noreply, refresh(socket) |> put_flash(:info, "Observação registrada.")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           observation_forms:
             Map.put(
               socket.assigns.observation_forms,
               release_id,
               to_form(changeset, as: :observation)
             )
         )}
    end
  end

  def handle_event("save_purchase", %{"release_id" => release_id, "purchase" => attrs}, socket) do
    attrs =
      attrs
      |> normalize_datetime("purchased_at")
      |> normalize_money("price_cents")
      |> Map.put("release_id", release_id)

    case Purchasing.create_purchase(socket.assigns.user, attrs) do
      {:ok, _purchase} ->
        {:noreply, refresh(socket) |> put_flash(:info, "Compra registrada e posse atualizada.")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           purchase_forms:
             Map.put(socket.assigns.purchase_forms, release_id, to_form(changeset, as: :purchase))
         )}
    end
  end

  def handle_event("save_veto", %{"release_id" => release_id, "veto" => attrs}, socket) do
    case Library.create_veto(socket.assigns.user, Map.merge(attrs, %{"release_id" => release_id})) do
      {:ok, _} ->
        {:noreply, refresh(socket) |> put_flash(:info, "Versão vetada.")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           veto_forms:
             Map.put(socket.assigns.veto_forms, release_id, to_form(changeset, as: :veto))
         )}
    end
  end

  def handle_event("undo_veto", %{"id" => id}, socket) do
    veto = Library.get_veto!(socket.assigns.user, id)
    {:ok, _} = Library.delete_veto(socket.assigns.user, veto)
    {:noreply, refresh(socket) |> put_flash(:info, "Veto desfeito.")}
  end

  def handle_event("save_entry", %{"entry" => attrs}, socket) do
    attrs = normalize_money(attrs, "target_price_cents")

    result =
      case socket.assigns.entry do
        nil ->
          Library.create_entry(
            socket.assigns.user,
            Map.put(attrs, "game_id", socket.assigns.game.id)
          )

        entry ->
          Library.update_entry(socket.assigns.user, entry, attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply, refresh(socket) |> put_flash(:info, "Entrada atualizada.")}

      {:error, changeset} ->
        {:noreply, assign(socket, entry_form: to_form(changeset, as: :entry))}
    end
  end

  defp assign_game(socket, user, game) do
    ownerships = Library.list_ownerships(user) |> Enum.filter(&(&1.release.game_id == game.id))
    purchases = Purchasing.list_purchases(user) |> Enum.filter(&(&1.release.game_id == game.id))
    entry = Library.get_entry_for_game(user, game.id)

    assign(socket,
      page_title: game.title,
      game: game,
      user: user,
      entry: entry,
      entry_form: entry_form(entry, game.id),
      ownerships: ownerships,
      purchases: purchases,
      ownerships_by_release: Enum.group_by(ownerships, & &1.release_id),
      purchases_by_release: Enum.group_by(purchases, & &1.release_id),
      observation_forms: %{},
      purchase_forms: %{},
      veto_forms: %{}
    )
  end

  defp refresh(socket) do
    game = Catalog.get_game!(socket.assigns.game.id)
    assign_game(socket, socket.assigns.user, game)
  end

  defp entry_form(nil, game_id), do: to_form(%{"game_id" => game_id}, as: :entry)
  defp entry_form(entry, _game_id), do: to_form(Ecto.Changeset.change(entry), as: :entry)

  defp release_title(%{platform: platform, edition: edition}) do
    if edition in [nil, "", "Edição padrão"],
      do: enum_label(platform),
      else: "#{enum_label(platform)} · #{edition}"
  end

  defp release_status(%{release_date: date} = release) when not is_nil(date) do
    if Date.compare(date, Date.utc_today()) == :gt,
      do: "Lançamento em #{release_date_label(release)}",
      else: "Data de lançamento #{release_date_label(release)}"
  end

  defp release_status(%{physical_available: true}), do: "Disponível em físico"
  defp release_status(%{digital_available: true}), do: "Disponível em digital"
  defp release_status(_), do: "Disponibilidade não informada"

  defp release_date_label(%{release_date: date, release_date_precision: :day}),
    do: date_pt_br(date)

  defp release_date_label(%{release_date: date, release_date_precision: :month}),
    do: Calendar.strftime(date, "%m/%Y")

  defp release_date_label(%{release_date: date, release_date_precision: :quarter}) do
    quarter = div(date.month - 1, 3) + 1
    "#{quarter}º tri. de #{date.year}"
  end

  defp release_date_label(%{release_date: date, release_date_precision: :year}),
    do: Integer.to_string(date.year)

  defp release_date_label(%{release_date: date, release_date_precision: :tbd}),
    do: "#{date.year}, a definir"

  defp release_date_label(%{release_date: date}), do: date_pt_br(date)

  defp ownership_label(ownerships_by_release, release_id) do
    ownerships_by_release
    |> Map.get(release_id, [])
    |> Enum.map_join(" e ", &enum_label(&1.ownership_type))
  end

  defp normalize_datetime(attrs, key) do
    case attrs[key] do
      value when is_binary(value) and byte_size(value) > 0 ->
        Map.put(attrs, key, parse_datetime(value))

      _ ->
        attrs
    end
  end

  defp parse_datetime(value) do
    case DateTime.from_iso8601(
           String.replace(value, " ", "T") <>
             if(String.ends_with?(value, "Z"), do: "", else: ":00Z")
         ) do
      {:ok, datetime, _} -> datetime
      _ -> value
    end
  end

  defp normalize_money(attrs, key) do
    case DockdWeb.DockdComponents.parse_money(Map.get(attrs, key)) do
      {:ok, nil} -> Map.put(attrs, key, nil)
      {:ok, cents} -> Map.put(attrs, key, cents)
      :error -> attrs
    end
  end
end
