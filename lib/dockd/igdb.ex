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

  def search(title) when is_binary(title) do
    if configured?(),
      do:
        post(
          "games",
          "search \"#{escape(title)}\"; fields id,name,cover.image_id,summary,platforms.id,platforms.name,release_dates.date,release_dates.platform,involved_companies.company.name,involved_companies.developer,involved_companies.publisher; limit 10;"
        ),
      else: {:error, :not_configured}
  end

  def get_games(ids) when is_list(ids) do
    if configured?(),
      do:
        post(
          "games",
          "where id = (#{Enum.join(ids, ",")}); fields id,name,cover.image_id,involved_companies.company.name,involved_companies.developer,involved_companies.publisher,platforms.id,platforms.name,release_dates.date,release_dates.platform; limit #{length(ids)};"
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
  @moduledoc "Supervised daily synchronization timer for linked catalog games."
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  @impl true
  def init(_) do
    interval =
      Application.get_env(:dockd, :igdb, []) |> Keyword.get(:sync_interval, :timer.hours(24))

    schedule(interval)
    {:ok, interval}
  end

  @impl true
  def handle_info(:sync, interval) do
    _ = Dockd.Catalog.sync_igdb()
    schedule(interval)
    {:noreply, interval}
  end

  defp schedule(interval),
    do: if(Dockd.IGDB.configured?(), do: Process.send_after(self(), :sync, interval))
end
