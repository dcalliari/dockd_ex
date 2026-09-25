defmodule DockdWeb.LibraryLive do
  @moduledoc "Biblioteca: every game the owner relates to, one status each, as a grid of covers."
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Library.Shelf

  @filters ~w(tab plat media q sort)

  @impl true
  def mount(_params, _session, socket) do
    user = Accounts.default_owner()
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
  def handle_event("filter", params, socket) do
    filters = socket.assigns.filters |> Map.merge(Map.take(params, @filters)) |> compact()
    {:noreply, push_patch(socket, to: ~p"/?#{filters}")}
  end

  def handle_event("search", %{"q" => q}, socket) do
    filters = socket.assigns.filters |> Map.put("q", q) |> compact()
    {:noreply, push_patch(socket, to: ~p"/?#{filters}")}
  end

  defp compact(filters),
    do: filters |> Enum.reject(fn {_k, v} -> v in ["", nil, "todos", "titulo"] end) |> Map.new()

  defp tab_path(filters, tab), do: ~p"/?#{compact(Map.put(filters, "tab", tab))}"

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
    <Layouts.app flash={@flash} current="Biblioteca" search={@filters["q"] || ""} search_live>
      <.tabs id="library-tabs">
        <:tab
          :for={tab <- Shelf.tabs()}
          label={tab_label(tab)}
          count={@counts[tab]}
          selected={(@filters["tab"] || "todos") == tab}
          patch={tab_path(@filters, tab)}
        />
      </.tabs>

      <form id="library-filters" class="dk-toolbar" phx-change="filter">
        <div class="dk-filters">
          <select name="plat" class="dk-select" aria-label="Plataforma">
            <option value="">Plataforma</option>
            <option value="switch" selected={@filters["plat"] == "switch"}>Switch</option>
            <option value="switch_2" selected={@filters["plat"] == "switch_2"}>Switch 2</option>
          </select>
          <select name="media" class="dk-select" aria-label="Mídia">
            <option value="">Mídia</option>
            <option value="physical" selected={@filters["media"] == "physical"}>Físico</option>
            <option value="digital" selected={@filters["media"] == "digital"}>Digital</option>
          </select>
          <select name="sort" class="dk-select" aria-label="Ordem">
            <option value="titulo">Título</option>
            <option value="lancamento" selected={@filters["sort"] == "lancamento"}>Lançamento</option>
          </select>
        </div>
        <span id="library-count" class="dk-count">{count_label(length(@visible))}</span>
      </form>

      <div :if={@visible != []} id="library-grid" class="dk-grid">
        <.link
          :for={item <- @visible}
          id={"shelf-#{item.game.id}"}
          navigate={~p"/jogos/#{item.game.id}"}
          class="dk-card"
          data-status={item.status}
        >
          <.poster
            title={item.game.title}
            cover_url={item.game.cover_url}
            status={item.status}
            faded={item.status in [:zerado, :larguei]}
          />
          <span class="dk-card__text">
            <span class="dk-card__title">{item.game.title}</span>
            <span class="dk-card__meta">
              {meta([platform_label(item.releases), item.year])}
            </span>
          </span>
        </.link>
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
