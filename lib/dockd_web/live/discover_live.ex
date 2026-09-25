defmodule DockdWeb.DiscoverLive do
  @moduledoc """
  Descobrir: busca no catálogo inteiro do IGDB, restrita a Switch e Switch 2.

  Sem credenciais do IGDB a busca cai para o catálogo local, o que mantém o fluxo
  utilizável em desenvolvimento e nos testes.
  """
  use DockdWeb, :live_view

  alias Dockd.{Accounts, Catalog, Library}
  alias Dockd.Library.Shelf

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Descobrir", user: Accounts.default_owner())}

  @impl true
  def handle_params(params, _uri, socket) do
    q = params |> Map.get("q", "") |> String.trim()
    {:noreply, socket |> assign(q: q) |> search()}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/descobrir?#{%{q: String.trim(q)}}")}

  def handle_event("want", %{"igdb_id" => igdb_id}, socket) do
    case Catalog.import_igdb(String.to_integer(igdb_id)) do
      {:ok, game} -> want(socket, game)
      {:error, _} -> {:noreply, put_flash(socket, :error, "Não foi possível importar o jogo.")}
    end
  end

  def handle_event("want", %{"game_id" => game_id}, socket),
    do: want(socket, Catalog.get_game!(game_id))

  defp want(socket, game) do
    user = socket.assigns.user

    result =
      case Library.get_entry_for_game(user, game.id) do
        nil -> Library.create_entry(user, %{game_id: game.id, purchase_intent: :want})
        entry -> Library.update_entry(user, entry, %{purchase_intent: :want})
      end

    case result do
      {:ok, _} -> {:noreply, search(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Não foi possível adicionar.")}
    end
  end

  defp search(%{assigns: %{q: ""}} = socket), do: assign(socket, results: [], source: nil)

  defp search(%{assigns: %{q: q, user: user}} = socket) do
    shelf = user |> Shelf.list() |> Map.new(&{&1.game.id, &1.status})

    {source, results} =
      case Catalog.search_igdb(q) do
        {:ok, results} -> {:igdb, results}
        {:error, _} -> {:local, local_results(q)}
      end

    results =
      Enum.map(results, fn result ->
        Map.put(result, :status, result.game && shelf[result.game.id])
      end)

    assign(socket, results: results, source: source)
  end

  defp local_results(q) do
    needle = String.downcase(q)

    Catalog.list_games()
    |> Enum.filter(&String.contains?(String.downcase(&1.title), needle))
    |> Enum.map(fn game ->
      releases = game.releases || []

      %{
        igdb_id: game.igdb_id,
        title: game.title,
        cover_url: game.cover_url,
        platforms: releases |> Enum.map(& &1.platform) |> Enum.uniq() |> Enum.sort(),
        year:
          releases
          |> Enum.map(& &1.release_date)
          |> Enum.reject(&is_nil/1)
          |> case do
            [] -> nil
            dates -> dates |> Enum.min(Date) |> Map.fetch!(:year)
          end,
        game: game
      }
    end)
  end

  defp result_id(%{game: %{id: id}}), do: "result-#{id}"
  defp result_id(%{igdb_id: igdb_id}), do: "result-igdb-#{igdb_id}"

  defp want_values(%{game: %{id: id}}), do: %{"phx-value-game_id" => id}
  defp want_values(%{igdb_id: igdb_id}), do: %{"phx-value-igdb_id" => igdb_id}

  defp count_label(1), do: "1 jogo"
  defp count_label(n), do: "#{n} jogos"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current="Descobrir" search={@q}>
      <form
        id="discover-search"
        class="dk-search dk-search--lg"
        role="search"
        phx-change="search"
        phx-submit="search"
      >
        <.icon name="hero-magnifying-glass" />
        <input
          id="discover-q"
          type="search"
          name="q"
          value={@q}
          placeholder="Buscar no catálogo"
          aria-label="Buscar no catálogo"
          autocomplete="off"
          phx-debounce="300"
          autofocus
        />
      </form>

      <p :if={@q != ""} id="discover-count" class="dk-count">
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
            status={result.status}
            navigate={result.game && ~p"/jogos/#{result.game.id}"}
          />
          <span :if={is_nil(result.status)} class="dk-poster__veil">
            <.btn size="sm" class="discover-want" phx-click="want" {want_values(result)}>
              Quero jogar
            </.btn>
          </span>
          <span class="dk-tip" role="tooltip">
            {meta([Enum.map_join(result.platforms, " · ", &enum_label/1), result.year])}
          </span>
          <span class="dk-card__title">{result.title}</span>
          <.btn
            :if={is_nil(result.status)}
            size="sm"
            class="dk-card__action--touch discover-want"
            phx-click="want"
            {want_values(result)}
          >
            Quero jogar
          </.btn>
        </div>
      </div>

      <.empty_state :if={@q != "" and @results == []} id="discover-empty">
        Nenhum jogo com “{@q}” para Switch ou Switch 2.
      </.empty_state>
      <.empty_state :if={@q == ""} id="discover-hint">
        Busque um jogo pelo título para acompanhar o lançamento ou marcar Quero.
      </.empty_state>
    </Layouts.app>
    """
  end
end
