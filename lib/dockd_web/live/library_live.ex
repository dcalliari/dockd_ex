defmodule DockdWeb.LibraryLive do
  @moduledoc """
  Biblioteca: every game the owner relates to, one status each, as a grid of covers. At
  the same address a visitor gets the catalog showcase (`DockdWeb.Showcase`).

  A status change keeps the grid still: the card stays where it is with its new tag, and a
  cleared one shows + Adicionar until the tabs or filters change.
  """
  use DockdWeb, :live_view

  on_mount {DockdWeb.UserAuth, :require_authenticated}

  alias Dockd.Library
  alias Dockd.Library.Shelf
  alias DockdWeb.{GameEvents, Showcase, UserAuth}

  @filters ~w(tab plat media sort)
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
    items = Shelf.list(user)

    {:ok,
     socket
     |> assign(page_title: "Biblioteca", user: user, items: items, counts: Shelf.counts(items))
     |> GameEvents.init()}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{user: nil}} = socket), do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filters)

    {:noreply,
     assign(socket, filters: filters, visible: Shelf.filter(socket.assigns.items, filters))}
  end

  @impl true
  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &reload/1)

  defp reload(socket) do
    items = Shelf.list(socket.assigns.user)
    fresh = Map.new(items, &{&1.game.id, &1})

    visible =
      Enum.map(socket.assigns.visible, fn item ->
        Map.get(fresh, item.game.id, %{item | status: nil, entry: nil, ownerships: []})
      end)

    assign(socket, items: items, counts: Shelf.counts(items), visible: visible)
  end

  defp compact(filters),
    do: filters |> Enum.reject(fn {_k, v} -> v in ["", nil, "todos", "titulo"] end) |> Map.new()

  defp library_path(filters, key, value),
    do: ~p"/biblioteca?#{compact(Map.put(filters, key, value))}"

  defp tab_label("todos"), do: "Todos"
  defp tab_label("jogando"), do: "Jogando"
  defp tab_label("backlog"), do: "Backlog"
  defp tab_label("quero"), do: "Quero"
  defp tab_label("zerado"), do: "Zerados"

  defp count_label(1), do: "1 jogo"
  defp count_label(n), do: "#{n} jogos"

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
      current="Biblioteca"
    >
      <.tabs id="library-tabs">
        <:tab
          :for={tab <- Shelf.tabs()}
          label={tab_label(tab)}
          count={@counts[tab]}
          selected={(@filters["tab"] || "todos") == tab}
          patch={library_path(@filters, "tab", tab)}
        />
      </.tabs>

      <div id="library-filters" class="dk-toolbar">
        <div class="dk-filters">
          <.filter
            id="filter-plat"
            label="Plataforma"
            value={@filters["plat"] || ""}
            options={[{"", "Todas"}, {"switch", "Switch"}, {"switch_2", "Switch 2"}]}
            path={&library_path(@filters, "plat", &1)}
          />
          <.filter
            id="filter-media"
            label="Mídia"
            value={@filters["media"] || ""}
            options={[{"", "Qualquer"}, {"physical", "Físico"}, {"digital", "Digital"}]}
            path={&library_path(@filters, "media", &1)}
          />
          <.filter
            id="filter-sort"
            label="Ordem"
            value={@filters["sort"] || "titulo"}
            options={[{"titulo", "Título"}, {"lancamento", "Lançamento"}]}
            path={&library_path(@filters, "sort", &1)}
          />
        </div>
        <span id="library-count" class="dk-count">{count_label(Enum.count(@visible, & &1.status))}</span>
      </div>

      <div :if={@visible != []} id="library-grid" class="dk-grid">
        <div
          :for={item <- @visible}
          id={"shelf-#{item.game.id}"}
          class="dk-card"
          data-status={item.status}
        >
          <.poster
            title={item.game.title}
            cover_url={item.game.cover_url}
            faded={item.status in [:zerado, :larguei]}
            availability={item.game.availability}
            navigate={~p"/jogos/#{item.game.id}"}
          />
          <.status_menu
            id={"status-#{item.game.id}"}
            status={item.status}
            options={Library.status_options(item)}
            values={%{game_id: item.game.id}}
            ask={GameEvents.ask(@asking, item)}
          />
          <.link navigate={~p"/jogos/#{item.game.id}"} class="dk-card__text">
            <span class="dk-card__title">{item.game.title}</span>
            <span class="dk-card__meta">
              {meta([platform_label(item.releases), item.year])}
            </span>
          </.link>
        </div>
      </div>

      <.empty_state :if={@visible == [] and @items == []} id="library-empty">
        Sua biblioteca está vazia. <.link navigate={~p"/descobrir"}>Descobrir jogos</.link>
      </.empty_state>
      <.empty_state :if={@visible == [] and @items != []} id="library-empty">
        Nada aqui. <.link patch={~p"/biblioteca"}>Ver todos</.link>
      </.empty_state>
    </Layouts.app>
    """
  end
end
