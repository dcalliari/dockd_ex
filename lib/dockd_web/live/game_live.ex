defmodule DockdWeb.GameLive do
  @moduledoc """
  Página do jogo: capa, o controle de status, versões com preço e o histórico. O
  visitante vê só a ficha do catálogo, e a etiqueta + Adicionar leva ao Entrar e volta com
  o controle aberto (`abrir`).
  """
  use DockdWeb, :live_view

  alias Dockd.{Activity, Catalog, Library, Purchasing}
  alias Dockd.Library.Shelf
  alias DockdWeb.{GameEvents, UserAuth}

  @game_events GameEvents.events()

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user
    game = Catalog.get_game!(id)

    {:ok,
     socket
     |> assign(page_title: game.title, user: user, game: game, form: nil)
     |> GameEvents.init(params["abrir"])
     |> UserAuth.halt_visitor_events([])
     |> load()}
  end

  defp load(%{assigns: %{user: nil, game: game}} = socket),
    do: assign(socket, item: Shelf.item(nil, game), observations: %{}, history: [], since: nil)

  defp load(socket) do
    %{user: user, game: game} = socket.assigns
    item = Shelf.item(user, game)

    observations =
      Map.new(item.releases, &{&1.id, Purchasing.latest_price_observation(user, &1.id)})

    assign(socket,
      item: item,
      observations: observations,
      history: history(user, item),
      since: since(item)
    )
  end

  # ---------------------------------------------------------------------------
  # Status, Comprei and prices, inline

  @impl true
  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &load/1)

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, form: nil)}

  def handle_event("price_form", %{"release_id" => release_id}, socket),
    do: {:noreply, assign(socket, form: {:price, release_id})}

  def handle_event("buy_form", _params, socket), do: {:noreply, assign(socket, form: :buy)}

  def handle_event("save_price", %{"release_id" => release_id} = params, socket) do
    with {:ok, cents} when is_integer(cents) <- parse_money(params["price"]),
         {:ok, _} <-
           Purchasing.create_price_observation(socket.assigns.user, %{
             release_id: release_id,
             format: params["format"] || "digital",
             price_cents: cents,
             observed_at: DateTime.utc_now(),
             source: blank_to(params["source"], "eShop")
           }) do
      {:noreply, socket |> assign(form: nil) |> load()}
    else
      {:ok, nil} -> {:noreply, put_flash(socket, :error, "Informe o preço visto.")}
      :error -> {:noreply, put_flash(socket, :error, "Preço inválido. Use 199,90.")}
      {:error, changeset} -> {:noreply, put_flash(socket, :error, error_message(changeset))}
    end
  end

  defp blank_to(value, default) when value in [nil, ""], do: default
  defp blank_to(value, _default), do: value

  defp error_message(%Ecto.Changeset{} = changeset) do
    case Keyword.values(changeset.errors) do
      [{message, _} | _] -> message
      _ -> "Não foi possível salvar."
    end
  end

  # ---------------------------------------------------------------------------
  # Read model for the page

  defp since(%Shelf{entry: nil}), do: nil
  defp since(%Shelf{entry: entry}), do: entry.updated_at

  defp history(user, %Shelf{game: game, ownerships: ownerships, releases: releases}) do
    release_names = Map.new(releases, &{&1.id, enum_label(&1.platform)})

    events =
      user
      |> Activity.list_events()
      |> Enum.filter(&(&1.game_id == game.id))
      |> Enum.map(&event_item(&1, release_names))
      |> Enum.reject(&is_nil/1)

    owned =
      Enum.map(ownerships, fn o ->
        %{
          what: "Registrou a posse",
          at: o.acquired_at,
          who: [enum_label(o.ownership_type), release_names[o.release_id]]
        }
      end)

    prices =
      Enum.flat_map(releases, fn r ->
        user
        |> Purchasing.list_price_observations(r.id)
        |> Enum.map(fn p ->
          %{
            what: "Viu o preço: #{money(p.price_cents, p.currency)}",
            at: p.observed_at,
            who: [p.source, enum_label(p.format), release_names[r.id]]
          }
        end)
      end)

    items = Enum.sort_by(events ++ owned ++ prices, & &1.at, {:desc, DateTime})

    case Enum.find_index(items, & &1[:state]) do
      nil -> items
      index -> List.update_at(items, index, &Map.put(&1, :current, true))
    end
  end

  @state_events %{
    added: "Entrou na biblioteca",
    started: "Começou a jogar",
    resumed: "Voltou a jogar",
    paused: "Pausou",
    finished: "Zerou",
    abandoned: "Largou",
    removed: "Saiu da biblioteca"
  }
  @other_events %{purchased: "Comprou", vetoed: "Não quer esta versão"}

  defp event_item(event, release_names) do
    who = [release_names[event.release_id]]

    cond do
      what = @state_events[event.type] ->
        %{what: what, at: event.occurred_at, who: who, state: true}

      what = @other_events[event.type] ->
        %{what: what, at: event.occurred_at, who: who}

      true ->
        nil
    end
  end

  defp igdb_url(%{igdb_id: nil}), do: nil
  defp igdb_url(%{slug: slug}), do: "https://www.igdb.com/games/#{slug}"

  defp ownership_for(item, release_id),
    do: Enum.find(item.ownerships, &(&1.release_id == release_id))

  defp exclusive?(game), do: game.availability in [:nintendo_exclusive, :switch2_exclusive]

  defp default_price(nil), do: ""

  defp default_price(observation),
    do: observation.price_cents |> money() |> String.replace("R$ ", "")

  # Comprei offers the version out first, preselected.
  defp buy_releases(item) do
    first = Shelf.first_release(item)
    [first | List.delete(item.releases, first)]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={@user && "Biblioteca"}
    >
      <p class="dk-back">
        <.link :if={@user} id="game-back" navigate={~p"/"} class="dk-link">
          <.icon name="hero-arrow-left" /> Biblioteca
        </.link>
        <.link :if={!@user} id="game-back" navigate={~p"/descobrir"} class="dk-link">
          <.icon name="hero-arrow-left" /> Descobrir
        </.link>
      </p>

      <section id="game-hero" class="dk-hero">
        <div>
          <.poster title={@game.title} cover_url={@game.cover_url} />
          <.poster_caption
            platforms={platform_label(@item.releases)}
            exclusive={exclusive?(@game)}
          />
        </div>
        <div class="dk-hero__text">
          <h1 class="t-display">{@game.title}</h1>
          <p id="game-meta" class="t-meta">{meta([@game.developer, @item.year])}</p>

          <.status_link
            :if={!@user}
            id="game-sign-in"
            size="md"
            back={~p"/jogos/#{@game.id}?#{%{abrir: "status"}}"}
          />
          <.status_menu
            :if={@user}
            id="game-status"
            size="md"
            status={@item.status}
            since={@since}
            options={Library.status_options(@item)}
            values={%{game_id: @game.id}}
            open={@status_open != nil}
            ask={GameEvents.ask(@asking, @item)}
          />

          <div
            :if={@user != nil and @item.status in [nil, :quero] and @item.releases != []}
            class="dk-hero__actions"
          >
            <.btn :if={@form != :buy} id="buy-button" variant="primary" phx-click="buy_form">
              Comprei
            </.btn>
            <.purchase_form
              :if={@form == :buy}
              id="buy-form"
              releases={buy_releases(@item)}
              price={default_price(@observations[Shelf.first_release(@item).id])}
            />
          </div>
        </div>
      </section>

      <.section_head title="Versões" count={length(@item.releases)} />
      <div :for={release <- @item.releases} id={"release-#{release.id}"}>
        <div class="dk-row dk-row--wide">
          <.date_block date={release.release_date} precision={release.release_date_precision} />
          <div>
            <span class="dk-row__title">{release_label(release)}</span>
            <div class="dk-row__meta">
              <%= if ownership = ownership_for(@item, release.id) do %>
                Tem · <.media_tag media={ownership.ownership_type} />
                desde {date_pt_br(ownership.acquired_at)}
              <% else %>
                {meta([
                  release.physical_available && "Físico",
                  release.digital_available && "Digital",
                  release.physical_is_key_card && "Key card"
                ])}
              <% end %>
            </div>
          </div>
          <div :if={@user} class="dk-row__end">
            <.price id={"price-#{release.id}"} observation={@observations[release.id]} />
            <.btn size="sm" phx-click="price_form" phx-value-release_id={release.id}>
              Registrar preço
            </.btn>
          </div>
        </div>

        <form
          :if={@form == {:price, release.id}}
          id={"price-form-#{release.id}"}
          class="dk-inline-form"
          phx-submit="save_price"
        >
          <input type="hidden" name="release_id" value={release.id} />
          <input
            type="text"
            name="price"
            inputmode="decimal"
            placeholder="199,90"
            aria-label="Preço visto"
            value={default_price(@observations[release.id])}
            autofocus
          />
          <select name="format" aria-label="Mídia">
            <option value="digital">Digital</option>
            <option value="physical">Físico</option>
          </select>
          <input type="text" name="source" placeholder="eShop" aria-label="Onde viu" />
          <.btn type="submit" size="sm" variant="primary">Salvar preço</.btn>
          <button type="button" class="dk-link" phx-click="cancel">Cancelar</button>
        </form>
      </div>

      <.section_head :if={@history != []} title="Histórico" />
      <.history :if={@history != []} id="game-history" items={@history} />
      <.igdb_credit id="game-credit" url={igdb_url(@game)} />
    </Layouts.app>
    """
  end
end
