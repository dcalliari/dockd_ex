defmodule Dockd.Eshop do
  @moduledoc """
  Small client for the Nintendo eShop Brasil: the nintendo.com title search (Algolia)
  and the public price API.

  Neither endpoint is an official, documented API. Both are public and keyless apart
  from the search-only key that nintendo.com hands to every browser, read here from
  configuration because Nintendo may rotate it. Requests go one per second, with a
  User-Agent naming Dockd, and never disguise themselves.
  """
  @price_url "https://api.ec.nintendo.com/v1/price"
  @default_app_id "U3B6GR4UA3"
  @indexes %{pt_br: "store_game_pt_br", en_us: "store_game_en_us"}
  @price_batch 50
  # HTTP headers are ASCII only.
  @user_agent "Dockd/#{Mix.Project.config()[:version]} (personal game library; prices once a day)"
  @search_fields ~w(nsuid title platformCode eshopDetails.productType dlcType isUpgrade)

  def price_batch, do: @price_batch

  # Compose passes an unset variable as an empty string.
  defp app_id do
    case config(:algolia_app_id) do
      id when is_binary(id) and id != "" -> id
      _ -> @default_app_id
    end
  end

  @doc "Whether the title search has a key. Prices need none."
  def configured? do
    key = config(:algolia_search_key)
    is_binary(key) and key != ""
  end

  @doc """
  Searches the eShop catalog of a locale (`:pt_br` or `:en_us`) by title. Returns
  `{:ok, hits}`, each hit as the index stores it.
  """
  def search(locale, query) when is_map_key(@indexes, locale) and is_binary(query) do
    if configured?() do
      app_id = app_id()

      :post
      |> request("https://#{app_id}-dsn.algolia.net/1/indexes/#{@indexes[locale]}/query",
        headers: [
          {"x-algolia-application-id", app_id},
          {"x-algolia-api-key", config(:algolia_search_key)}
        ],
        json: %{
          query: query,
          hitsPerPage: 10,
          attributesToRetrieve: @search_fields,
          attributesToHighlight: [],
          attributesToSnippet: []
        }
      )
      |> body_field("hits")
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Brazilian prices for up to #{@price_batch} nsuids. Returns `{:ok, prices}` in the
  API's shape: `title_id`, `sales_status` and, when sold, `regular_price` and
  `discount_price` with its window.
  """
  def prices(nsuids) when is_list(nsuids) and length(nsuids) in 1..@price_batch do
    :get
    |> request(@price_url, params: [country: "BR", lang: "pt", ids: Enum.join(nsuids, ",")])
    |> body_field("prices")
  end

  # A changed endpoint answers 200 with another shape: an error, not a crash.
  defp body_field({:ok, %{body: %{} = body}}, key) when is_map_key(body, key),
    do: {:ok, Map.fetch!(body, key)}

  defp body_field({:ok, _unexpected}, _key), do: {:error, :unexpected_response}
  defp body_field(error, _key), do: error

  defp request(method, url, options) do
    {headers, options} = Keyword.pop(options, :headers, [])

    [method: method, url: url, retry: false, headers: [{"user-agent", @user_agent} | headers]]
    |> Keyword.merge(options)
    |> Keyword.merge(config(:req_options, []))
    |> send_request(0)
  end

  defp send_request(options, attempt) do
    throttle()

    case Req.request(options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{status: status, body: body}}

      {:ok, %{status: status}} when (status == 429 or status >= 500) and attempt < 3 ->
        Process.sleep(backoff(attempt))
        send_request(options, attempt + 1)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.TransportError{}} when attempt < 3 ->
        Process.sleep(backoff(attempt))
        send_request(options, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp backoff(attempt), do: min(2_000 * Integer.pow(2, attempt), 16_000)

  defp throttle do
    interval = config(:throttle_ms, 1_000)
    now = System.monotonic_time(:millisecond)
    previous = :persistent_term.get({__MODULE__, :last_request}, now - interval)
    if previous + interval > now, do: Process.sleep(previous + interval - now)
    :persistent_term.put({__MODULE__, :last_request}, System.monotonic_time(:millisecond))
  end

  defp config(key, default \\ nil),
    do: Application.get_env(:dockd, :eshop, []) |> Keyword.get(key, default)
end
