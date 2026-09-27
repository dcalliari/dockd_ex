defmodule Dockd.IGDB do
  @moduledoc """
  Small IGDB client with token caching, throttling and retry handling.
  """
  @switch_id 130
  @switch_2_id 508
  @token_margin 60_000

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
          "search \"#{escape(title)}\"; fields id,name,alternative_names.name,cover.image_id,summary,platforms.id,platforms.name,release_dates.date,release_dates.date_format,release_dates.category,release_dates.region,release_dates.platform,involved_companies.company.name,involved_companies.developer,involved_companies.publisher; where platforms = (#{@switch_id},#{@switch_2_id}); limit 20;"
        ),
      else: {:error, :not_configured}
  end

  @showcase_fields "fields id,name,cover.image_id,platforms.id,release_dates.date,release_dates.date_format,release_dates.category,release_dates.region,release_dates.platform,involved_companies.company.name,involved_companies.developer,involved_companies.publisher"

  @doc """
  A showcase list of Switch and Switch 2 works with a cover:

    * `:upcoming` not out yet, soonest first;
    * `:recent` out in the last 90 days, most followed first;
    * `:popular` out in the last year, most followed first.
  """
  def showcase(list, limit \\ 50) when list in [:upcoming, :recent, :popular] do
    if configured?(),
      do:
        post(
          "games",
          "#{@showcase_fields}; where platforms = (#{@switch_id},#{@switch_2_id}) & cover != null & #{showcase_where(list)}; limit #{limit};"
        ),
      else: {:error, :not_configured}
  end

  defp showcase_where(:upcoming),
    do: "first_release_date > #{System.os_time(:second)}; sort first_release_date asc"

  defp showcase_where(:recent), do: released_since(90)
  defp showcase_where(:popular), do: released_since(365)

  defp released_since(days) do
    now = System.os_time(:second)

    "first_release_date <= #{now} & first_release_date > #{now - days * 86_400} & version_parent = null; sort hypes desc"
  end

  def get_games(ids) when is_list(ids) do
    if configured?(),
      do:
        post(
          "games",
          "where id = (#{Enum.join(ids, ",")}); fields id,name,alternative_names.name,cover.image_id,involved_companies.company.name,involved_companies.developer,involved_companies.publisher,platforms.id,platforms.name,release_dates.date,release_dates.date_format,release_dates.category,release_dates.region,release_dates.platform; limit #{length(ids)};"
        ),
      else: {:error, :not_configured}
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

  defp throttle do
    now = System.monotonic_time(:millisecond)
    previous = :persistent_term.get({__MODULE__, :last_request}, now - 100)
    if previous + 100 > now, do: Process.sleep(previous + 100 - now)
    :persistent_term.put({__MODULE__, :last_request}, System.monotonic_time(:millisecond))
  end

  defp req_options(options), do: Keyword.merge(options, config(:req_options, []))

  defp config(key, default \\ nil),
    do: Application.get_env(:dockd, :igdb, []) |> Keyword.get(key, default)
end

defmodule Dockd.IGDB.SyncScheduler do
  @moduledoc """
  Supervised scheduler that, on boot and daily, matches and synchronizes the catalog
  with IGDB and then the eShop Brasil prices (`Dockd.Pricing.sync_eshop/1`).
  """
  use GenServer

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
    _ = Dockd.Catalog.sync_igdb()
    _ = Dockd.Pricing.sync_eshop()
  end

  defp schedule(interval), do: Process.send_after(self(), :sync, interval)
end
