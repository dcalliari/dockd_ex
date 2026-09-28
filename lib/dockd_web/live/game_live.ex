defmodule DockdWeb.GameLive do
  @moduledoc """
  Página do jogo: capa, o controle de status, versões com preço e o histórico. O
  visitante vê só a ficha do catálogo, e a etiqueta + Adicionar leva ao Entrar e volta com
  o controle aberto (`abrir`).
  """
  use DockdWeb, :live_view

  alias Dockd.{Activity, Catalog, Library, Pricing, Purchasing}
  alias Dockd.Catalog.Release
  alias Dockd.Library.Shelf
  alias DockdWeb.{GameEvents, UserAuth}

  @game_events GameEvents.events()

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user
    game = Catalog.get_game!(id)

    {:ok,
     socket
     |> assign(page_title: game.title, user: user, game: game, editions_open: MapSet.new())
     |> GameEvents.init(params["abrir"])
     |> UserAuth.halt_visitor_events([])
     |> load()}
  end

  defp load(%{assigns: %{user: nil, game: game}} = socket) do
    item = Shelf.item(nil, game)

    assign(socket,
      item: item,
      versions: versions(item, %{}),
      withdrawn: MapSet.new(),
      sales: Pricing.sales_statuses(Enum.map(item.releases, & &1.id)),
      prices: %{},
      purchases: %{},
      history: [],
      since: nil
    )
  end

  defp load(socket) do
    %{user: user, game: game} = socket.assigns
    item = Shelf.item(user, game)
    purchases = Purchasing.list_purchases_for_game(user, game.id)
    prices = Map.new(item.releases, &{&1.id, Purchasing.current_price(user, &1.id)})

    assign(socket,
      item: item,
      versions: versions(item, prices),
      withdrawn: MapSet.new(for r <- item.releases, Pricing.withdrawn?(r.id), do: r.id),
      sales: Pricing.sales_statuses(Enum.map(item.releases, & &1.id)),
      prices: prices,
      purchases: Map.new(purchases, &{&1.id, &1}),
      history: history(user, item, purchases),
      since: since(item)
    )
  end

  # ---------------------------------------------------------------------------
  # Status, Comprei and prices: every event is a game event

  @impl true
  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &load/1)

  def handle_event("editions", %{"platform" => platform}, socket) do
    open = socket.assigns.editions_open

    open =
      if MapSet.member?(open, platform),
        do: MapSet.delete(open, platform),
        else: MapSet.put(open, platform)

    {:noreply, assign(socket, :editions_open, open)}
  end

  # ---------------------------------------------------------------------------
  # Read model for the page

  @shown_editions 2

  # Versões (maquetes/edicoes.html): one row per platform with its standard edition, and
  # under it the editions the store sells, cheapest first, or the one owned. Past the two
  # cheapest, Mais N edições opens the rest in place. An edition on a platform without
  # its standard one stands on its own row.
  defp versions(item, prices) do
    {standard, editions} = Enum.split_with(item.releases, &Release.standard?/1)

    editions =
      editions
      |> Enum.filter(&(prices[&1.id] || ownership_for(item, &1.id)))
      |> Enum.sort_by(&{is_nil(prices[&1.id]), prices[&1.id] && prices[&1.id].price_cents})
      |> Enum.group_by(& &1.platform)

    rows =
      Enum.map(standard, fn release ->
        {shown, more} = split_editions(item, Map.get(editions, release.platform, []))
        %{release: release, editions: shown, more: more}
      end)

    alone =
      for {platform, list} <- editions,
          platform not in Enum.map(standard, & &1.platform),
          release <- list,
          do: %{release: release, editions: [], more: []}

    Enum.sort_by(rows ++ alone, &{&1.release.platform, !Release.standard?(&1.release)})
  end

  defp editions_open?(version, open),
    do: MapSet.member?(open, to_string(version.release.platform))

  defp shown_editions(version, open),
    do: version.editions ++ if(editions_open?(version, open), do: version.more, else: [])

  # The owned editions always show; of the others, the two cheapest.
  defp split_editions(item, editions) do
    {owned, others} = Enum.split_with(editions, &ownership_for(item, &1.id))
    {shown, more} = Enum.split(others, @shown_editions)
    {Enum.filter(editions, &(&1 in owned or &1 in shown)), more}
  end

  defp since(%Shelf{entry: nil}), do: nil
  defp since(%Shelf{entry: entry}), do: entry.updated_at

  # An ownership that came with a purchase is told by the purchase, which carries the
  # price and defined the Backlog.
  defp history(user, %Shelf{game: game, ownerships: ownerships, releases: releases}, purchases) do
    release_names = Map.new(releases, &{&1.id, release_label(&1)})
    purchases = Map.new(purchases, &{&1.id, &1})

    events =
      user
      |> Activity.list_events()
      |> Enum.filter(&(&1.game_id == game.id))
      |> Enum.map(&event_item(&1, release_names, purchases))
      |> Enum.reject(&is_nil/1)

    owned =
      ownerships
      |> Enum.reject(& &1.purchase_id)
      |> Enum.map(fn o ->
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
  @other_events %{vetoed: "Não quer esta versão"}

  defp event_item(%{type: :purchased} = event, release_names, purchases) do
    purchase = purchases[event.payload["purchase_id"]]
    price = purchase && purchase.price_cents

    %{
      what: if(price, do: "Comprou: #{money(price, purchase.currency)}", else: "Comprou"),
      at: event.occurred_at,
      who: [
        release_names[event.release_id],
        purchase && enum_label(purchase.format),
        purchase && purchase.retailer
      ],
      state: true
    }
  end

  defp event_item(event, release_names, _purchases) do
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

  defp paid_cents(purchases, %{purchase_id: id}) when is_binary(id),
    do: purchases[id] && purchases[id].price_cents

  defp paid_cents(_purchases, _ownership), do: nil

  defp ownership_for(item, release_id),
    do: Enum.find(item.ownerships, &(&1.release_id == release_id))

  defp exclusive?(game), do: game.availability in [:nintendo_exclusive, :switch2_exclusive]

  defp price_open?(%{kind: :price, key: key}, release_id), do: key == release_id
  defp price_open?(_form, _release_id), do: false

  defp buyable?(assigns),
    do:
      assigns.user != nil and assigns.item.releases != [] and
        (assigns.item.status in [nil, :quero] or Map.has_key?(assigns.bought, assigns.game.id))

  # What the eShop says of a version not out yet; the date alone may not tell.
  @not_out %{"preorder" => "pré-venda", "unreleased" => "não lançado"}
  defp not_out(sales_status), do: @not_out[sales_status]

  attr :release, :map, required: true
  attr :title, :string, required: true
  attr :item, :map, required: true
  attr :purchases, :map, required: true
  attr :user, :map, default: nil
  attr :game_id, :string, required: true
  attr :price, :map, default: nil
  attr :withdrawn, :boolean, default: false
  attr :sales_status, :string, default: nil
  attr :form, :map, default: nil
  attr :form_error, :string, default: nil
  attr :edition, :boolean, default: false, doc: "an edition under its platform's row"

  defp version_row(assigns) do
    ~H"""
    <div class={if(@edition, do: "dk-edition", else: "dk-row dk-row--wide")}>
      <.date_block
        :if={!@edition}
        date={@release.release_date}
        precision={@release.release_date_precision}
      />
      <div>
        <span class="dk-row__title">{@title}</span>
        <div class="dk-row__meta">
          <%= if ownership = ownership_for(@item, @release.id) do %>
            Tem · <.media_tag media={ownership.ownership_type} />
            <%= if paid = paid_cents(@purchases, ownership) do %>
              · pagou {money(paid)} em {date_pt_br(ownership.acquired_at)}
            <% else %>
              desde {date_pt_br(ownership.acquired_at)}
            <% end %>
            {if @withdrawn, do: " · fora de venda"}
          <% else %>
            {meta([
              @edition && "Pacote",
              @release.physical_available && "Físico",
              @release.digital_available && "Digital",
              @release.physical_is_key_card && "Key card",
              @withdrawn && "fora de venda",
              not_out(@sales_status)
            ])}
          <% end %>
        </div>
      </div>
      <div :if={@user} class="dk-row__end">
        <.price
          id={"price-#{@release.id}"}
          observation={@price}
          game_id={@game_id}
          release_id={@release.id}
          open={price_open?(@form, @release.id)}
        />
      </div>
    </div>
    <.price_form
      :if={price_open?(@form, @release.id)}
      id={"price-form-#{@release.id}"}
      form={@form}
      error={@form_error}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      catalog_review={@catalog_review}
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

          <div :if={buyable?(assigns)} class="dk-hero__actions">
            <.buy_control
              id="buy"
              place="hero"
              game_id={@game.id}
              choices={GameEvents.buying(@buying, @game.id)}
              purchase={@bought[@game.id]}
              form={@form}
              error={@form_error}
            />
          </div>
        </div>
      </section>
      <.buy_options
        :if={buyable?(assigns) and GameEvents.buy_options(@buying, @game.id)}
        id="buy-options"
        game_id={@game.id}
        options={GameEvents.buy_options(@buying, @game.id)}
      />

      <.section_head title="Versões" />
      <div :for={version <- @versions} id={"release-#{version.release.id}"} class="dk-version">
        <.version_row
          release={version.release}
          title={
            if(Release.standard?(version.release),
              do: enum_label(version.release.platform),
              else: release_label(version.release)
            )
          }
          item={@item}
          purchases={@purchases}
          user={@user}
          game_id={@game.id}
          price={@prices[version.release.id]}
          withdrawn={MapSet.member?(@withdrawn, version.release.id)}
          sales_status={@sales[version.release.id]}
          form={@form}
          form_error={@form_error}
        />
        <ul :if={version.editions != [] or version.more != []} class="dk-editions">
          <li
            :for={edition <- shown_editions(version, @editions_open)}
            id={"release-#{edition.id}"}
          >
            <.version_row
              release={edition}
              title={edition.edition}
              item={@item}
              purchases={@purchases}
              user={@user}
              game_id={@game.id}
              price={@prices[edition.id]}
              withdrawn={MapSet.member?(@withdrawn, edition.id)}
              sales_status={@sales[edition.id]}
              form={@form}
              form_error={@form_error}
              edition
            />
          </li>
          <li :if={version.more != []} class="dk-editions__more">
            <button
              id={"editions-#{version.release.platform}"}
              type="button"
              class="dk-link"
              phx-click="editions"
              phx-value-platform={version.release.platform}
            >
              {if editions_open?(version, @editions_open),
                do: "Menos edições",
                else: more_editions(length(version.more))}
            </button>
          </li>
        </ul>
      </div>

      <.section_head :if={@history != []} title="Histórico" />
      <.history :if={@history != []} id="game-history" items={@history} />
      <p :if={igdb_url(@game)} id="game-igdb" class="dk-credit">
        <a href={igdb_url(@game)} target="_blank" rel="noopener noreferrer">Mais informações no IGDB</a>
      </p>
    </Layouts.app>
    """
  end
end
