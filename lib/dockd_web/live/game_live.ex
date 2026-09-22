defmodule DockdWeb.GameLive do
  use DockdWeb, :live_view

  alias Dockd.{Accounts, Catalog, Library, Purchasing}

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    game = Catalog.get_game!(id)
    user = Accounts.default_owner()
    entry = Library.get_entry_for_game(user, game.id)
    return_context = return_context(Map.get(params, "from"))

    {:ok,
     assign(socket,
       page_title: game.title,
       game: game,
       user: user,
       entry: entry,
       owned?: game.id in Library.owned_game_ids(user),
       return_to: return_context.path,
       return_label: return_context.label,
       entry_form: entry_form(entry, game.id),
       release_data: release_data(game, user, entry),
       observation_forms: %{},
       purchase_forms: %{},
       veto_forms: %{}
     )}
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
      {:ok, purchase} ->
        ownership_type = if attrs["format"] == "physical", do: :physical, else: :digital

        Library.create_ownership(socket.assigns.user, %{
          release_id: release_id,
          ownership_type: ownership_type,
          acquired_at: purchase.purchased_at,
          purchase_id: purchase.id
        })

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

  defp refresh(socket) do
    game = Catalog.get_game!(socket.assigns.game.id)
    entry = Library.get_entry_for_game(socket.assigns.user, game.id)

    assign(socket,
      game: game,
      entry: entry,
      owned?: game.id in Library.owned_game_ids(socket.assigns.user),
      entry_form: entry_form(entry, game.id),
      release_data: release_data(game, socket.assigns.user, entry),
      observation_forms: %{},
      purchase_forms: %{},
      veto_forms: %{}
    )
  end

  defp release_data(game, user, entry) do
    Enum.map(game.releases, fn release ->
      observations = Purchasing.list_price_observations(user, release.id)
      observation = List.first(observations)
      veto = Library.get_veto_for_release(user, release.id)

      %{
        release: release,
        observations: observations,
        observation: observation,
        veto: veto,
        verdict: release_verdict(observation, veto, entry)
      }
    end)
  end

  defp release_verdict(_observation, veto, _entry) when not is_nil(veto), do: "Vetada"
  defp release_verdict(nil, _veto, _entry), do: "Sem preço"

  defp release_verdict(observation, _veto, entry) do
    cond do
      Purchasing.stale?(observation, DateTime.utc_now()) -> "Desatualizado"
      is_nil(entry) or is_nil(entry.target_price_cents) -> "Sem alvo"
      observation.price_cents <= entry.target_price_cents -> "Abaixo do alvo"
      true -> "Esperar"
    end
  end

  defp return_context("planner"), do: %{path: "/", label: "Planejador"}
  defp return_context("library"), do: %{path: "/biblioteca", label: "Biblioteca"}
  defp return_context(_), do: %{path: "/catalogo", label: "Descobrir"}

  defp entry_form(nil, game_id), do: to_form(%{"game_id" => game_id}, as: :entry)
  defp entry_form(entry, _game_id), do: to_form(Ecto.Changeset.change(entry), as: :entry)

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
