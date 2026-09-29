defmodule Dockd.IGDB do
  @moduledoc """
  Small IGDB client with token caching, throttling and retry handling.
  """
  @switch_id 130
  @switch_2_id 508
  @token_margin 60_000

  # What says an entry is another entry's edition, Switch 2 Edition, remaster or port.
  @family_fields "version_parent,version_title,parent_game,game_type"

  def switch_platform_id, do: @switch_id
  def switch_2_platform_id, do: @switch_2_id

  def configured? do
    is_binary(config(:client_id)) and config(:client_id) != "" and
      is_binary(config(:client_secret)) and config(:client_secret) != ""
  end

  @doc """
  Searches IGDB by title, restricted to works with a Switch or Switch 2 platform.

  The platform filter lives in the query itself: an unfiltered search for "zelda"
  returns NES and Game Boy entries first and no Nintendo Switch release at all.
  """
  def search(title) when is_binary(title) do
    if configured?(),
      do:
        post(
          "games",
          "search \"#{escape(title)}\"; fields id,name,slug,alternative_names.name,cover.image_id,summary,platforms.id,platforms.name,release_dates.date,release_dates.date_format,release_dates.category,release_dates.region,release_dates.platform,involved_companies.company.name,involved_companies.developer,involved_companies.publisher,#{@family_fields}; where platforms = (#{@switch_id},#{@switch_2_id}); limit 20;"
        ),
      else: {:error, :not_configured}
  end

  @catalog_page 500

  @doc """
  What the catalog criterion reads (`Dockd.Catalog.Curation`) of every Switch and Switch
  2 entry of `game_types` that is not an edition of another one, every page of them.
  """
  def catalog_entries(game_types) do
    where =
      "platforms = (#{@switch_id},#{@switch_2_id}) & version_parent = null & game_type = (#{Enum.join(game_types, ",")})"

    pages(
      "fields id,name,alternative_names.name,cover.image_id,platforms.id,game_type,game_status,parent_game,version_parent,total_rating_count,aggregated_rating_count,hypes,involved_companies.company.name,involved_companies.publisher,release_dates.date,release_dates.date_format,release_dates.category,release_dates.region,release_dates.platform; where #{where}"
    )
  end

  @doc "How many Switch and Switch 2 entries of a `game_type` there are, and a few of them."
  def catalog_sample(game_type, limit \\ 5) do
    where =
      "where platforms = (#{@switch_id},#{@switch_2_id}) & version_parent = null & game_type = #{game_type}"

    with {:ok, %{body: %{"count" => count}}} <- post("games/count", "#{where};"),
         {:ok, %{body: sample}} <-
           post("games", "fields name; #{where}; sort total_rating_count desc; limit #{limit};") do
      {:ok, count, Enum.map(sample, & &1["name"])}
    end
  end

  @doc "The entries IGDB lists inside the bundles `ids`: their games and add-ons."
  def bundle_contents(ids) when is_list(ids) and ids != [],
    do:
      pages(
        "fields id,name,game_type,version_parent,bundles,platforms.id; where bundles = (#{Enum.join(ids, ",")})"
      )

  @doc "The rating counts of `ids`, the games that others remaster or port."
  def rating_counts(ids) when is_list(ids) and ids != [] do
    ids
    |> Enum.chunk_every(@catalog_page)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, found} ->
      case post(
             "games",
             "fields id,total_rating_count; where id = (#{Enum.join(chunk, ",")}); limit #{@catalog_page};"
           ) do
        {:ok, %{body: page}} -> {:cont, {:ok, found ++ page}}
        error -> {:halt, error}
      end
    end)
  end

  defp pages(query) do
    if configured?(), do: pages(query, 0, []), else: {:error, :not_configured}
  end

  defp pages(query, offset, found) do
    case post("games", "#{query}; sort id asc; limit #{@catalog_page}; offset #{offset};") do
      {:ok, %{body: page}} when length(page) == @catalog_page ->
        pages(query, offset + @catalog_page, found ++ page)

      {:ok, %{body: page}} ->
        {:ok, found ++ page}

      error ->
        error
    end
  end

  def get_games(ids) when is_list(ids) do
    if configured?(),
      do:
        post(
          "games",
          "where id = (#{Enum.join(ids, ",")}); fields id,name,slug,alternative_names.name,cover.image_id,involved_companies.company.name,involved_companies.developer,involved_companies.publisher,platforms.id,platforms.name,release_dates.date,release_dates.date_format,release_dates.category,release_dates.region,release_dates.platform,total_rating_count,hypes,#{@family_fields}; limit #{length(ids)};"
        ),
      else: {:error, :not_configured}
  end

  @children_page 500

  @doc """
  The Switch and Switch 2 entries that are an edition (`version_parent`) or a child
  (`parent_game`: remaster, expanded game, port, Switch 2 Edition) of any of `ids`,
  every page of them.
  """
  def children(ids) when is_list(ids) and ids != [] do
    if configured?(), do: children(Enum.join(ids, ","), 0, []), else: {:error, :not_configured}
  end

  defp children(ids, offset, found) do
    query =
      "where (version_parent = (#{ids}) | parent_game = (#{ids})) & platforms = (#{@switch_id},#{@switch_2_id}); fields id,name,platforms.id,release_dates.date,release_dates.date_format,release_dates.category,release_dates.region,release_dates.platform,#{@family_fields}; sort id asc; limit #{@children_page}; offset #{offset};"

    case post("games", query) do
      {:ok, %{body: page}} when length(page) == @children_page ->
        children(ids, offset + @children_page, found ++ page)

      {:ok, %{body: page}} ->
        {:ok, found ++ page}

      error ->
        error
    end
  end

  defp escape(value), do: String.replace(value, "\\", "\\\\") |> String.replace("\"", "\\\"")

  defp post(path, query) do
    with {:ok, token} <- access_token() do
      request(:post, "https://api.igdb.com/v4/#{path}",
        headers: [
          {"authorization", "Bearer #{token}"},
          {"client-id", config(:client_id)},
          {"content-type", "text/plain"}
        ],
        body: query
      )
    end
  end

  defp access_token do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, :token}, nil) do
      {token, expires} when expires > now + @token_margin ->
        {:ok, token}

      _ ->
        with {:ok, response} <-
               request(:post, "https://id.twitch.tv/oauth2/token",
                 params: [
                   client_id: config(:client_id),
                   client_secret: config(:client_secret),
                   grant_type: "client_credentials"
                 ]
               ),
             %{"access_token" => token, "expires_in" => seconds} <- response.body do
          :persistent_term.put({__MODULE__, :token}, {token, now + seconds * 1000})
          {:ok, token}
        else
          _ -> {:error, :authentication_failed}
        end
    end
  end

  def clear_cache, do: :persistent_term.erase({__MODULE__, :token})

  defp request(method, url, options, attempt \\ 0) do
    throttle()
    options = Keyword.merge([method: method, url: url, retry: false], options)

    case Req.request(req_options(options)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{status: status, body: body}}

      {:ok, %{status: status}} when (status == 429 or status >= 500) and attempt < 3 ->
        Process.sleep(backoff(attempt))
        request(method, url, options, attempt + 1)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, _reason} when attempt < 3 ->
        Process.sleep(backoff(attempt))
        request(method, url, options, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp backoff(attempt), do: min(1_000 * Integer.pow(2, attempt), 8_000)

  # IGDB allows four requests per second.
  defp throttle do
    interval = Application.get_env(:dockd, :igdb_throttle_ms, 250)
    now = System.monotonic_time(:millisecond)
    previous = :persistent_term.get({__MODULE__, :last_request}, now - interval)
    if previous + interval > now, do: Process.sleep(previous + interval - now)
    :persistent_term.put({__MODULE__, :last_request}, System.monotonic_time(:millisecond))
  end

  defp req_options(options), do: Keyword.merge(options, config(:req_options, []))

  defp config(key, default \\ nil),
    do: Application.get_env(:dockd, :igdb, []) |> Keyword.get(key, default)
end

defmodule Dockd.IGDB.SyncScheduler do
  @moduledoc """
  Supervised scheduler that, on boot and daily, brings in the IGDB games that the
  catalog criterion admits (`Dockd.Catalog.curate/1`), synchronizes the catalog with
  IGDB and then the eShop Brasil products and prices (`Dockd.Pricing.sync_eshop/1`).
  Every step resumes where the previous run stopped.
  """
  use GenServer
  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    config = Application.get_env(:dockd, :igdb, [])
    interval = Keyword.get(config, :sync_interval, :timer.hours(24))
    initial_delay = Keyword.get(config, :sync_initial_delay, 1_000)

    Process.send_after(self(), :initial_sync, initial_delay)
    {:ok, interval}
  end

  @impl true
  def handle_info(:initial_sync, interval) do
    run_sync()
    schedule(interval)
    {:noreply, interval}
  end

  @impl true
  def handle_info(:sync, interval) do
    run_sync()
    schedule(interval)
    {:noreply, interval}
  end

  defp run_sync do
    _ = Dockd.Catalog.match_igdb()

    case Dockd.Catalog.curate() do
      {:ok, report} -> Logger.info("Catálogo: #{report.imported} jogos novos")
      {:error, :not_configured} -> :ok
      {:error, reason} -> Logger.error("Catálogo: curadoria falhou: #{inspect(reason)}")
    end

    _ = Dockd.Catalog.sync_igdb()
    _ = Dockd.Pricing.sync_eshop()
  end

  defp schedule(interval), do: Process.send_after(self(), :sync, interval)
end
