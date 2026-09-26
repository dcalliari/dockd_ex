defmodule DockdWeb.LibraryLive do
  @moduledoc "Biblioteca: every game the owner relates to, one status each, as a grid of covers."
  use DockdWeb, :live_view

  alias Dockd.{Catalog, Library}
  alias Dockd.Library.Shelf

  @filters ~w(tab plat media sort)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    items = Shelf.list(user)

    {:ok,
     assign(socket,
       page_title: "Biblioteca",
       user: user,
       items: items,
       counts: Shelf.counts(items)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filters)

    {:noreply,
     assign(socket, filters: filters, visible: Shelf.filter(socket.assigns.items, filters))}
  end

  @impl true
  def handle_event("set_status", %{"game_id" => game_id, "status" => status}, socket) do
    game = Catalog.get_game!(game_id)
    status = Enum.find(statuses(), &(Atom.to_string(&1) == status))

    case Library.set_status(socket.assigns.user, game, status) do
      {:ok, _} -> {:noreply, reload(socket)}
      {:error, :needs_ownership} -> {:noreply, push_navigate(socket, to: ~p"/jogos/#{game.id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Não foi possível mudar o status.")}
    end
  end

  def handle_event("remove", %{"game_id" => game_id}, socket) do
    {:ok, :ok} = Library.remove_game(socket.assigns.user, Catalog.get_game!(game_id))
    {:noreply, reload(socket)}
  end

  defp reload(socket) do
    items = Shelf.list(socket.assigns.user)

    assign(socket,
      items: items,
      counts: Shelf.counts(items),
      visible: Shelf.filter(items, socket.assigns.filters)
    )
  end

  # Backlog stays available without ownership: the game page asks the version.
  defp available(%{ownerships: []}), do: statuses()
  defp available(_owned), do: statuses() -- [:quero]

  defp compact(filters),
    do: filters |> Enum.reject(fn {_k, v} -> v in ["", nil, "todos", "titulo"] end) |> Map.new()

  defp library_path(filters, key, value), do: ~p"/?#{compact(Map.put(filters, key, value))}"

  defp tab_label("todos"), do: "Todos"
  defp tab_label("jogando"), do: "Jogando"
  defp tab_label("backlog"), do: "Backlog"
  defp tab_label("quero"), do: "Quero"
  defp tab_label("zerado"), do: "Zerados"

  defp count_label(1), do: "1 jogo"
  defp count_label(n), do: "#{n} jogos"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current="Biblioteca">
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
        <span id="library-count" class="dk-count">{count_label(length(@visible))}</span>
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
            navigate={~p"/jogos/#{item.game.id}"}
          />
          <.status_menu
            id={"status-#{item.game.id}"}
            status={item.status}
            available={available(item)}
            values={%{game_id: item.game.id}}
          />
          <button
            type="button"
            class="dk-card__trash"
            aria-label={"Tirar #{item.game.title} da biblioteca"}
            phx-click="remove"
            phx-value-game_id={item.game.id}
            data-confirm={"Tirar #{item.game.title} da biblioteca?"}
          >
            <.icon name="hero-trash" />
          </button>
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
        Nada aqui. <.link patch={~p"/"}>Ver todos</.link>
      </.empty_state>
    </Layouts.app>
    """
  end
end
