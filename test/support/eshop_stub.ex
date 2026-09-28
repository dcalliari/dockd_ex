defmodule Dockd.EshopStub do
  @moduledoc """
  Answers eShop requests in tests with responses recorded from Nintendo on
  2026-09-27 and 2026-09-28 (`test/support/fixtures/eshop`). A product page is recorded
  as the part of its `__NEXT_DATA__` that describes the product and its relatives
  (`product--<nsuid>.json`), served back inside a page. A request without a recording fails
  the test instead of reaching the network. Each request is reported to the test
  process as `{:eshop_request, kind, detail, user_agent}`.
  """
  import ExUnit.Assertions

  @fixtures Path.expand("fixtures/eshop", __DIR__)
  @name "eshop"
  @american_pages ["70010000107421", "70070000037147"]

  def name, do: @name

  def config(extra \\ []) do
    Keyword.merge(
      [
        algolia_search_key: "test-search-key",
        throttle_ms: 0,
        req_options: [plug: {Req.Test, @name}]
      ],
      extra
    )
  end

  @doc "Stubs search and price with the recordings; `prices` overrides the price entries."
  def stub(test_pid, prices \\ recorded_prices()) do
    Req.Test.stub(@name, fn conn -> respond(conn, test_pid, prices) end)
  end

  def recorded_prices, do: read!("price_br.json")["prices"]

  def fixture(name), do: read!(name)

  defp respond(%{host: "api.ec.nintendo.com"} = conn, test_pid, prices) do
    conn = Plug.Conn.fetch_query_params(conn)
    assert %{"country" => "BR", "ids" => ids} = conn.query_params
    ids = String.split(ids, ",")
    assert length(ids) <= 50
    report(test_pid, conn, :price, ids)

    by_id = Map.new(prices, &{to_string(&1["title_id"]), &1})

    found =
      Enum.map(ids, fn id ->
        Map.get(by_id, id) || flunk("no recorded eShop price for #{id}")
      end)

    Req.Test.json(conn, %{"personalized" => false, "country" => "BR", "prices" => found})
  end

  defp respond(%{host: "www.nintendo.com"} = conn, test_pid, _prices) do
    [locale, "store", "products", nsuid] = conn.path_info
    report(test_pid, conn, :product, {locale, nsuid})
    file = "product--#{nsuid}.json"

    cond do
      # Recorded from the Brazilian page, except those only the American one has.
      locale == "pt-br" and nsuid in @american_pages ->
        Plug.Conn.send_resp(conn, 404, "")

      File.exists?(Path.join(@fixtures, file)) ->
        data = @fixtures |> Path.join(file) |> File.read!()

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(
          200,
          ~s(<html><body><script id="__NEXT_DATA__" type="application/json">#{data}</script></body></html>)
        )

      true ->
        flunk("no recorded eShop product page for #{locale} #{nsuid}")
    end
  end

  defp respond(conn, test_pid, _prices) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"query" => query} = request = Jason.decode!(body)
    ["1", "indexes", index, "query"] = conn.path_info
    [app_id] = Plug.Conn.get_req_header(conn, "x-algolia-application-id")
    assert conn.host == "#{app_id}-dsn.algolia.net" and app_id =~ ~r/^[A-Z0-9]+$/
    report(test_pid, conn, :search, {index, query})

    # The popularity ranking is an empty query filtered by rank.
    file =
      case request["numericFilters"] do
        ["popularityRank>" <> low, "popularityRank<=" <> high] ->
          "#{index}--popular-#{low}-#{high}.json"

        nil ->
          "#{index}--#{slug(query)}.json"
      end

    if File.exists?(Path.join(@fixtures, file)),
      do: Req.Test.json(conn, read!(file)),
      else: flunk("no recorded eShop search for #{index} #{inspect(query)}")
  end

  defp report(test_pid, conn, kind, detail),
    do:
      send(
        test_pid,
        {:eshop_request, kind, detail, List.first(Plug.Conn.get_req_header(conn, "user-agent"))}
      )

  defp read!(file), do: @fixtures |> Path.join(file) |> File.read!() |> Jason.decode!()

  defp slug(title) do
    title
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
