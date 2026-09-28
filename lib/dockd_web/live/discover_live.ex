defmodule DockdWeb.DiscoverLive do
  @moduledoc """
  Descobrir: busca no catálogo inteiro do IGDB e as listas da vitrine, restritas a Switch e
  Switch 2. É pública: para o visitante a etiqueta de status leva ao Entrar e volta aqui,
  com o menu daquela capa aberto (`abrir`).

  Sem credenciais do IGDB a busca cai para o catálogo local, o que mantém o fluxo
  utilizável em desenvolvimento e nos testes.
  """
  use DockdWeb, :live_view

  alias Dockd.{Catalog, Library}
  alias Dockd.Library.Shelf
  alias DockdWeb.{GameEvents, UserAuth}

  @game_events GameEvents.events()

  # Showcase lists by their `lista` value; the first one opens Descobrir without a search.
  @lists [
    {"lancamentos", :upcoming, "Próximos lançamentos"},
    {"recentes", :recent, "Chegaram agora"},
    {"em-alta", :popular, "Em alta"}
  ]

  def lists, do: @lists

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(page_title: "Descobrir", user: user)
     |> GameEvents.init()
     |> UserAuth.halt_visitor_events(["search"])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    q = params |> Map.get("q", "") |> String.trim()
    list = List.keyfind(@lists, params["lista"], 0, hd(@lists))

    {:noreply, socket |> assign(q: q, list: list) |> GameEvents.init(params["abrir"]) |> search()}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/descobrir?#{%{q: String.trim(q)}}")}

  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &search/1)

  defp search(%{assigns: %{q: "", list: {_, list, _}}} = socket),
    do: assign(socket, results: with_status(Catalog.showcase(list), socket), source: :showcase)

  defp search(%{assigns: %{q: q}} = socket) do
    {source, results} = Catalog.search(q)
    assign(socket, results: with_status(results, socket), source: source)
  end

  # Each result carries its game's shelf item fields, so the status control reads it like
  # a Biblioteca card.
  defp with_status(results, %{assigns: %{user: user}}) do
    shelf = if user, do: user |> Shelf.list() |> Map.new(&{&1.game.id, &1}), else: %{}

    Enum.map(results, fn result ->
      item = result.game && shelf[result.game.id]

      Map.merge(result, %{
        status: item && item.status,
        ownerships: (item && item.ownerships) || []
      })
    end)
  end

  @doc "The DOM id of a result card, also the `abrir` value that opens its menu."
  def result_id(%{game: %{id: id}}), do: "result-#{id}"
  def result_id(%{igdb_id: igdb_id}), do: "result-igdb-#{igdb_id}"

  @doc "Descobrir on the showcase list `lista`, with extra query `params`."
  def list_path("lancamentos", params), do: ~p"/descobrir?#{params}"
  def list_path(lista, params), do: ~p"/descobrir?#{Map.put(params, :lista, lista)}"

  defp menu_values(%{game: %{id: id}}), do: %{game_id: id}
  defp menu_values(%{igdb_id: igdb_id}), do: %{igdb_id: igdb_id}

  @doc "Platforms and the release date, or the year once it is out."
  def result_meta(%{first_date: %Date{} = date, platforms: platforms} = result) do
    if Date.compare(date, Date.utc_today()) == :gt,
      do: meta([Enum.map_join(platforms, " · ", &enum_label/1), date_pt_br(date)]),
      else: meta([Enum.map_join(platforms, " · ", &enum_label/1), result.year])
  end

  def result_meta(result), do: Enum.map_join(result.platforms, " · ", &enum_label/1)

  # Where a visitor comes back to after Entrar: this same list, with the card's menu open.
  defp back_path(%{q: "", list: {lista, _, _}}, result),
    do: list_path(lista, %{abrir: result_id(result)})

  defp back_path(%{q: q}, result), do: ~p"/descobrir?#{%{q: q, abrir: result_id(result)}}"

  defp count_label(1), do: "1 jogo"
  defp count_label(n), do: "#{n} jogos"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      catalog_review={@catalog_review}
      current="Descobrir"
      search={@q}
      search_live
    >
      <.section_head
        :if={@source == :showcase and @results != []}
        id="discover-list"
        title={elem(@list, 2)}
      />
      <p
        :if={@q != ""}
        id="discover-count"
        class="dk-count"
        style="margin: var(--space-4) 0 var(--space-3)"
      >
        {count_label(length(@results))} para “{@q}”
      </p>

      <div :if={@results != []} id="discover-results" class="dk-grid">
        <div
          :for={result <- @results}
          id={result_id(result)}
          class="dk-card"
          data-status={result.status}
        >
          <.poster
            title={result.title}
            cover_url={result.cover_url}
            navigate={result.game && ~p"/jogos/#{result.game.id}"}
          />
          <.status_link :if={!@user} back={back_path(assigns, result)} />
          <.status_menu
            :if={@user}
            id={"status-#{result_id(result)}"}
            status={result.status}
            options={Library.status_options(result)}
            values={menu_values(result)}
            open={@status_open == result_id(result)}
            ask={GameEvents.ask(@asking, result)}
          />
          <span class="dk-card__text">
            <span class="dk-card__title">{result.title}</span>
            <span class="dk-card__meta">{result_meta(result)}</span>
          </span>
        </div>
      </div>

      <.empty_state :if={@q != "" and @results == []} id="discover-empty">
        Nenhum jogo com “{@q}” para Switch ou Switch 2.
      </.empty_state>
      <.empty_state :if={@q == "" and @results == []} id="discover-hint">
        Busque um jogo pelo título na barra acima.
      </.empty_state>
    </Layouts.app>
    """
  end
end
