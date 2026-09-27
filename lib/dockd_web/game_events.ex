defmodule DockdWeb.GameEvents do
  @moduledoc """
  The events a game answers to on every screen, handled once so the status control and
  Comprei do the same thing wherever they appear (design/README.md, Uma ação, um efeito).

  A LiveView delegates `events/0` here and passes the function that reloads what it shows:

      def handle_event(event, params, socket) when event in @game_events,
        do: GameEvents.handle_event(event, params, socket, &load/1)

  The screen keeps two assigns, set by `init/2`: `status_open`, a menu the URL asked to open
  (`abrir`), and `asking`, the game whose Backlog waits for the version it is owned in.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import DockdWeb.DockdComponents, only: [parse_money: 1, release_label: 1, enum_label: 1]

  alias Dockd.{Catalog, Library, Purchasing}
  alias Dockd.Library.Shelf

  @events ~w(set_status own close_status save_purchase)
  @media %{"physical" => :physical, "digital" => :digital}

  @doc "Event names handled here."
  def events, do: @events

  @doc "Closes every status menu, or opens the one the URL named."
  def init(socket, open \\ nil), do: socket |> assign(:status_open, open) |> assign(:asking, nil)

  @doc """
  The versions to own for the card of `item` (a shelf item or a Descobrir result), when
  its game is the one asking; nil otherwise.
  """
  def ask(nil, _item), do: nil

  def ask(asking, item) do
    game = Map.get(item, :game)
    igdb_id = Map.get(item, :igdb_id)

    if (game && game.id == asking.game.id) || (igdb_id && igdb_id == asking.game.igdb_id),
      do: asking.choices
  end

  def handle_event("set_status", %{"status" => status} = params, socket, reload) do
    with {:ok, status} <- parse_status(status),
         {:ok, game} <- resolve_game(params) do
      case Library.set_status(user(socket), game, status) do
        {:ok, _} -> {:noreply, socket |> init() |> reload.()}
        {:error, :needs_ownership} -> {:noreply, socket |> ask_ownership(game) |> reload.()}
        {:error, _} -> {:noreply, failed(socket)}
      end
    else
      _ -> {:noreply, failed(socket)}
    end
  end

  def handle_event(
        "own",
        %{"release_id" => release_id, "media" => media} = params,
        socket,
        reload
      ) do
    with {:ok, game} <- resolve_game(params),
         {:ok, _} <-
           Library.set_status(user(socket), game, :backlog,
             ownership: %{
               release_id: release_id,
               ownership_type: Map.get(@media, media, :digital)
             }
           ) do
      {:noreply, socket |> init() |> reload.()}
    else
      _ -> {:noreply, failed(socket)}
    end
  end

  def handle_event("close_status", _params, socket, _reload), do: {:noreply, init(socket)}

  def handle_event("save_purchase", %{"release_id" => release_id} = params, socket, reload) do
    with {:ok, cents} when is_integer(cents) <- parse_money(params["price"]),
         {:ok, _} <-
           Purchasing.create_purchase(user(socket), %{
             release_id: release_id,
             format: params["format"] || "digital",
             price_cents: cents,
             purchased_at: DateTime.utc_now(),
             retailer: blank_to(params["retailer"], "eShop")
           }) do
      {:noreply, socket |> assign(:form, nil) |> reload.()}
    else
      {:ok, nil} -> {:noreply, put_flash(socket, :error, "Informe o preço pago.")}
      :error -> {:noreply, put_flash(socket, :error, "Preço inválido. Use 199,90.")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Não foi possível registrar.")}
    end
  end

  defp user(socket), do: socket.assigns.current_scope.user

  # An empty status is the current tag clicked again: out of the library.
  defp parse_status(""), do: {:ok, nil}

  defp parse_status(status) do
    case Enum.find(Shelf.statuses(), &(Atom.to_string(&1) == status)) do
      nil -> :error
      status -> {:ok, status}
    end
  end

  defp resolve_game(%{"game_id" => game_id}), do: {:ok, Catalog.get_game!(game_id)}

  defp resolve_game(%{"igdb_id" => igdb_id}) do
    case Integer.parse(to_string(igdb_id)) do
      {id, ""} -> Catalog.import_igdb(id)
      _ -> :error
    end
  end

  defp resolve_game(_params), do: :error

  defp ask_ownership(socket, game) do
    game = Catalog.get_game!(game.id)

    choices =
      for release <- Enum.sort_by(game.releases, & &1.platform),
          media <- [:physical, :digital],
          do: %{
            release_id: release.id,
            media: media,
            label: "#{release_label(release)} · #{enum_label(media)}"
          }

    socket |> assign(:status_open, nil) |> assign(:asking, %{game: game, choices: choices})
  end

  defp failed(socket),
    do: socket |> init() |> put_flash(:error, "Não foi possível mudar o status.")

  defp blank_to(value, default) when value in [nil, ""], do: default
  defp blank_to(value, _default), do: value
end
