defmodule Dockd.EshopStub do
  @moduledoc """
  Answers eShop requests in tests with responses recorded from Nintendo on
  2026-09-27 (`test/support/fixtures/eshop`). A request without a recording fails
  the test instead of reaching the network. Each request is reported to the test
  process as `{:eshop_request, kind, detail, user_agent}`.
  """
  import ExUnit.Assertions

  @fixtures Path.expand("fixtures/eshop", __DIR__)
  @name "eshop"

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

  defp respond(conn, test_pid, _prices) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"query" => query} = Jason.decode!(body)
    ["1", "indexes", index, "query"] = conn.path_info
    report(test_pid, conn, :search, {index, query})

    file = "#{index}--#{slug(query)}.json"

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
