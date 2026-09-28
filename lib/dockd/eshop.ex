defmodule Dockd.Eshop do
  @moduledoc """
  Small client for the Nintendo eShop Brasil: the nintendo.com title search (Algolia)
  and the public price API.

  It also reads a product's page on nintendo.com/pt-br for what the search does not
  say: which products are the same game (`product/1`).

  None of these is an official, documented API. Both are public and keyless apart
  from the search-only key that nintendo.com hands to every browser, read here from
  configuration because Nintendo may rotate it. Requests go one per second, with a
  User-Agent naming Dockd, and never disguise themselves.
  """
  @price_url "https://api.ec.nintendo.com/v1/price"
  @product_url "https://www.nintendo.com/%{locale}/store/products/"
  # Games missing from the Brazilian store pages (Pokopia, Rayman) have an American one.
  @product_locales ["pt-br", "us"]
  @default_app_id "U3B6GR4UA3"
  @indexes %{pt_br: "store_game_pt_br", en_us: "store_game_en_us"}
  @price_batch 50
  # HTTP headers are ASCII only.
  @user_agent "Dockd/#{Mix.Project.config()[:version]} (personal game library; prices once a day)"
  @search_fields ~w(nsuid title url platformCode eshopDetails.productType dlcType isUpgrade)

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

  @platforms %{"NINTENDO_SWITCH" => :switch, "NINTENDO_SWITCH_2" => :switch_2}

  @doc """
  A product as its nintendo.com page describes it (the Brazilian one, else the
  American one), read from the data the page
  embeds for its own script (`__NEXT_DATA__`). Returns `{:ok, product}` with `nsuid`,
  `title`, `platform`, `bundle?` (a game sold with content), `upgrade?` and the
  related products, each `%{nsuid:, title:, platform:}`: `variations`, the products
  Nintendo groups as the same game (editions and, for a Switch 2 Edition, the Switch
  version and the upgrade pack); `contents`, what a bundle holds; `base`, what an
  upgrade pack upgrades. A page in another shape is `{:error, :unexpected_response}`.
  """
  def product(nsuid) when is_binary(nsuid), do: product(nsuid, @product_locales)

  defp product(nsuid, [locale | rest]) do
    url = String.replace(@product_url, "%{locale}", locale) <> nsuid <> "/"

    case request(:get, url, decode_body: false) do
      {:ok, %{body: html}} when is_binary(html) -> parse_product(html)
      {:ok, _} -> {:error, :unexpected_response}
      {:error, {:http_error, 404}} when rest != [] -> product(nsuid, rest)
      error -> error
    end
  end

  defp parse_product(html) do
    with [_, json] <-
           Regex.run(~r{<script id="__NEXT_DATA__" type="application/json">(.*?)</script>}s, html),
         {:ok, %{"props" => %{"pageProps" => page}}} <- Jason.decode(json),
         %{"analytics" => %{"product" => %{"sku" => sku}}, "initialApolloState" => state} <- page,
         %{"nsuid" => nsuid} = main <- state[product_key(sku)] do
      related = fn field -> main |> Map.get(field, []) |> List.wrap() |> refs(state) end

      {:ok,
       Map.merge(summary(main), %{
         nsuid: nsuid,
         bundle?: get_in(main, ["dlcType", "code"]) == "ROM_BUNDLE",
         upgrade?: main["isUpgrade"] == true,
         variations: related.("variations"),
         contents: related.("softwareContents"),
         base: related.("baseSoftware")
       })}
    else
      _ -> {:error, :unexpected_response}
    end
  end

  defp product_key(sku), do: ~s(Product:{"sku":"#{sku}"})

  # A variation wraps its product; contents and base are the reference itself.
  defp refs(items, state) do
    for item <- items,
        ref = get_in(item, ["product", "__ref"]) || item["__ref"],
        %{"nsuid" => nsuid} = product when is_binary(nsuid) <- [state[ref]],
        do: summary(product)
  end

  defp summary(product),
    do: %{
      nsuid: product["nsuid"],
      title: product["name"],
      platform: @platforms[get_in(product, ["platform", "code"])]
    }

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
