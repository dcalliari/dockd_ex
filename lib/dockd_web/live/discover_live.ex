defmodule DockdWeb.DiscoverLive do
  @moduledoc """
  Descobrir: busca no catálogo inteiro do IGDB, restrita a Switch e Switch 2.

  Sem credenciais do IGDB a busca cai para o catálogo local, o que mantém o fluxo
  utilizável em desenvolvimento e nos testes.
  """
  use DockdWeb, :live_view

  alias Dockd.{Catalog, Library}
  alias Dockd.Library.Shelf

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Descobrir", user: socket.assigns.current_scope.user)}

  @impl true
  def handle_params(params, _uri, socket) do
    q = params |> Map.get("q", "") |> String.trim()
    {:noreply, socket |> assign(q: q) |> search()}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/descobrir?#{%{q: String.trim(q)}}")}

  def handle_event("set_status", %{"status" => status} = params, socket) do
    status = Enum.find(statuses(), &(Atom.to_string(&1) == status))

    with {:ok, game} <- resolve_game(params),
         {:ok, _} <- Library.set_status(socket.assigns.user, game, status) do
      {:noreply, search(socket)}
    else
      {:error, :needs_ownership} ->
        {:ok, game} = resolve_game(params)
        {:noreply, push_navigate(socket, to: ~p"/jogos/#{game.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível adicionar.")}
    end
  end

  defp resolve_game(%{"game_id" => game_id}), do: {:ok, Catalog.get_game!(game_id)}
  defp resolve_game(%{"igdb_id" => igdb_id}), do: Catalog.import_igdb(String.to_integer(igdb_id))

  defp search(%{assigns: %{q: "", user: user}} = socket) do
    shelf = user |> Shelf.list() |> Map.new(&{&1.game.id, &1.status})

    results =
      case Catalog.upcoming_igdb() do
        {:ok, results} -> results
        {:error, _} -> local_upcoming()
      end

    assign(socket, results: with_status(results, shelf), source: :upcoming)
  end

  defp search(%{assigns: %{q: q, user: user}} = socket) do
    shelf = user |> Shelf.list() |> Map.new(&{&1.game.id, &1.status})

    {source, results} =
      case Catalog.search_igdb(q) do
        {:ok, results} -> {:igdb, results}
        {:error, _} -> {:local, local_results(q)}
      end

    assign(socket, results: with_status(results, shelf), source: source)
  end

  defp with_status(results, shelf),
    do: Enum.map(results, &Map.put(&1, :status, &1.game && shelf[&1.game.id]))

  defp local_upcoming do
    today = Date.utc_today()

    Catalog.list_games()
    |> Enum.filter(fn game ->
      Enum.any?(
        game.releases || [],
        &(&1.release_date && Date.compare(&1.release_date, today) == :gt)
      )
    end)
    |> local_shape()
    |> Enum.sort_by(& &1.first_date, Date)
  end

  defp local_results(q) do
    needle = String.downcase(q)

    Catalog.list_games()
    |> Enum.filter(&String.contains?(String.downcase(&1.title), needle))
    |> local_shape()
  end

  defp local_shape(games) do
    Enum.map(games, fn game ->
      releases = game.releases || []
      dates = releases |> Enum.map(& &1.release_date) |> Enum.reject(&is_nil/1)
      first = if dates == [], do: nil, else: Enum.min(dates, Date)

      %{
        igdb_id: game.igdb_id,
        title: game.title,
        cover_url: game.cover_url,
        platforms: releases |> Enum.map(& &1.platform) |> Enum.uniq() |> Enum.sort(),
        first_date: first,
        year: first && first.year,
        game: game
      }
    end)
  end

  defp result_id(%{game: %{id: id}}), do: "result-#{id}"
  defp result_id(%{igdb_id: igdb_id}), do: "result-igdb-#{igdb_id}"

  defp menu_values(%{game: %{id: id}}), do: %{game_id: id}
  defp menu_values(%{igdb_id: igdb_id}), do: %{igdb_id: igdb_id}

  defp result_meta(%{first_date: %Date{} = date, platforms: platforms} = result) do
    if Date.compare(date, Date.utc_today()) == :gt,
      do: meta([Enum.map_join(platforms, " · ", &enum_label/1), date_pt_br(date)]),
      else: meta([Enum.map_join(platforms, " · ", &enum_label/1), result.year])
  end

  defp result_meta(result), do: Enum.map_join(result.platforms, " · ", &enum_label/1)

  defp count_label(1), do: "1 jogo"
  defp count_label(n), do: "#{n} jogos"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current="Descobrir"
      search={@q}
      search_live
    >
      <.section_head
        :if={@source == :upcoming and @results != []}
        id="discover-upcoming"
        title="Próximos lançamentos"
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
          <.status_menu
            id={"status-#{result_id(result)}"}
            status={result.status}
            available={
              if(result.status in [:backlog, :jogando, :zerado, :larguei],
                do: statuses() -- [:quero],
                else: statuses()
              )
            }
            values={menu_values(result)}
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
