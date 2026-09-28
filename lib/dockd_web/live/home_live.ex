defmodule DockdWeb.HomeLive do
  @moduledoc """
  Início da conta: faixas pessoais que levam à Biblioteca, Comprar e Descobrir.
  Visitantes continuam vendo a vitrine pública em `DockdWeb.Showcase`.
  """
  use DockdWeb, :live_view

  alias Dockd.Catalog.Release
  alias Dockd.Library.Shelf
  alias Dockd.{Pricing, Purchasing}
  alias DockdWeb.{GameEvents, Showcase, UserAuth}

  @game_events GameEvents.events()

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: nil}} = socket) do
    {:ok,
     socket
     |> assign(page_title: "Dockd", user: nil, strips: Showcase.strips())
     |> UserAuth.halt_visitor_events([])}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(page_title: "Início", user: user)
     |> GameEvents.init()
     |> load()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &load/1)

  defp load(socket) do
    %{user: user} = socket.assigns
    items = Shelf.list(user)
    wanted = Enum.filter(items, &(&1.status == :quero))
    sales = items |> Enum.flat_map(& &1.releases) |> Enum.map(& &1.id) |> Pricing.sales_statuses()
    prices = Map.new(wanted, &{&1.game.id, Purchasing.current_game_price(user, &1.releases)})

    assign(socket,
      playing: Enum.filter(items, &(&1.status == :jogando)) |> Enum.take(7),
      promotions:
        wanted
        |> Enum.filter(&promotion?(prices[&1.game.id]))
        |> Enum.sort_by(&prices[&1.game.id].price_cents)
        |> Enum.take(7),
      upcoming:
        wanted
        |> Enum.filter(&(next_release(&1, sales) != nil))
        |> Enum.sort_by(&next_release(&1, sales).release_date, Date)
        |> Enum.take(7),
      prices: prices,
      sales: sales
    )
  end

  defp promotion?(%{discount_ends_at: %DateTime{}}), do: true
  defp promotion?(_price), do: false

  defp next_release(item, sales) do
    item.releases
    |> Enum.filter(&(Release.launch(&1, Date.utc_today(), sales[&1.id]) == :upcoming))
    |> Enum.min_by(& &1.release_date, Date, fn -> nil end)
  end

  defp card_meta(item, nil), do: platform_label(item.releases)

  defp card_meta(item, release),
    do: meta([platform_label(item.releases), date_pt_br(release.release_date)])

  @impl true
  def render(%{user: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} catalog_review={@catalog_review}>
      <Showcase.showcase strips={@strips} />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      catalog_review={@catalog_review}
      current="Início"
    >
      <.section_head
        :if={@playing != []}
        id="home-playing"
        title="Jogando agora"
        count={length(@playing)}
      >
        <:action><.link navigate={~p"/biblioteca?tab=jogando"}>Ver Biblioteca</.link></:action>
      </.section_head>
      <div :if={@playing != []} id="home-playing-strip" class="dk-strip dk-home-strip">
        <.home_card :for={item <- @playing} item={item} rail="playing" asking={@asking} />
      </div>

      <.section_head
        :if={@promotions != []}
        id="home-promotions"
        title="Em promoção"
        count={length(@promotions)}
      >
        <:action><.link navigate={~p"/comprar"}>Ver Comprar</.link></:action>
      </.section_head>
      <div :if={@promotions != []} id="home-promotions-strip" class="dk-strip dk-home-strip">
        <.home_card
          :for={item <- @promotions}
          item={item}
          rail="promotions"
          price={@prices[item.game.id]}
          asking={@asking}
        />
      </div>

      <.section_head
        :if={@upcoming != []}
        id="home-upcoming"
        title="Da sua lista"
        count={length(@upcoming)}
      >
        <:action>
          <.link navigate={~p"/biblioteca?sort=lancamento&tab=quero"}>Ver todos</.link>
        </:action>
      </.section_head>
      <div :if={@upcoming != []} id="home-upcoming-strip" class="dk-strip dk-home-strip">
        <.home_card
          :for={item <- @upcoming}
          item={item}
          rail="upcoming"
          release={next_release(item, @sales)}
          asking={@asking}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :item, :map, required: true
  attr :rail, :string, required: true
  attr :price, :map, default: nil
  attr :release, :map, default: nil
  attr :asking, :map, required: true

  defp home_card(assigns) do
    ~H"""
    <div id={"home-#{@rail}-#{@item.game.id}"} class="dk-card" data-status={@item.status}>
      <.poster
        title={@item.game.title}
        cover_url={@item.game.cover_url}
        faded={@item.status in [:zerado, :larguei]}
        availability={@item.game.availability}
        navigate={~p"/jogos/#{@item.game.id}"}
      />
      <.status_menu
        id={"home-status-#{@rail}-#{@item.game.id}"}
        status={@item.status}
        options={Dockd.Library.status_options(@item)}
        values={%{game_id: @item.game.id}}
        ask={GameEvents.ask(@asking, @item)}
      />
      <.link navigate={~p"/jogos/#{@item.game.id}"} class="dk-card__text">
        <span class="dk-card__title">{@item.game.title}</span>
        <span class="dk-card__meta">{card_meta(@item, @release)}</span>
      </.link>
      <.price :if={@price} observation={@price} />
    </div>
    """
  end
end
