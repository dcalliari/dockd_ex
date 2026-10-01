defmodule DockdWeb.BrandAssetsTest do
  use DockdWeb.ConnCase

  defp head(conn) do
    conn |> html_response(200) |> LazyHTML.from_document()
  end

  defp meta(document, attr, name) do
    document
    |> LazyHTML.query(~s|meta[#{attr}="#{name}"]|)
    |> LazyHTML.attribute("content")
    |> List.first()
  end

  test "the root layout declares the favicon set", %{conn: conn} do
    document = head(get(conn, ~p"/"))

    hrefs =
      document
      |> LazyHTML.query(~s|link[rel="icon"]|)
      |> LazyHTML.attribute("href")
      |> Enum.sort()

    assert hrefs == ["/favicon.ico", "/favicon.svg"]

    assert document
           |> LazyHTML.query(~s|link[rel="apple-touch-icon"]|)
           |> LazyHTML.attribute("href") == ["/apple-touch-icon.png"]

    assert document
           |> LazyHTML.query(~s|link[rel="manifest"]|)
           |> LazyHTML.attribute("href") == ["/site.webmanifest"]
  end

  test "the default page has Open Graph and Twitter tags with an absolute image", %{conn: conn} do
    document = head(get(conn, ~p"/"))
    endpoint_url = DockdWeb.Endpoint.url()

    assert meta(document, "property", "og:title") == "Dockd"
    assert meta(document, "property", "og:description") =~ "biblioteca de jogos"
    assert meta(document, "property", "og:url") == endpoint_url <> "/"
    assert meta(document, "property", "og:image") == endpoint_url <> "/images/og.png"
    assert meta(document, "property", "og:image:width") == "1200"
    assert meta(document, "property", "og:image:height") == "630"
    assert meta(document, "name", "twitter:card") == "summary_large_image"
    assert meta(document, "name", "twitter:title") == "Dockd"
    assert meta(document, "name", "twitter:image") == endpoint_url <> "/images/og.png"
  end

  test "a page with its own title carries it and its own address", %{conn: conn} do
    document = head(get(conn, ~p"/sobre"))

    assert meta(document, "property", "og:title") == "Sobre · Dockd"
    assert meta(document, "name", "twitter:title") == "Sobre · Dockd"
    assert meta(document, "property", "og:url") == DockdWeb.Endpoint.url() <> "/sobre"
  end

  describe "static files" do
    for {path, type} <- [
          {"/favicon.ico", "image/"},
          {"/favicon.svg", "image/svg+xml"},
          {"/apple-touch-icon.png", "image/png"},
          {"/icon-192.png", "image/png"},
          {"/icon-512.png", "image/png"},
          {"/icon-maskable-512.png", "image/png"},
          {"/images/og.png", "image/png"},
          {"/site.webmanifest", "application/"}
        ] do
      test "#{path} is served", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert response(conn, 200) != ""
        assert [content_type] = get_resp_header(conn, "content-type")
        assert content_type =~ unquote(type)
      end
    end

    test "the thumbnail is 1200 by 630", %{conn: conn} do
      <<137, 80, 78, 71, 13, 10, 26, 10, _length::32, "IHDR", width::32, height::32, _::binary>> =
        conn |> get(~p"/images/og.png") |> response(200)

      assert {width, height} == {1200, 630}
    end

    test "the manifest is valid JSON that points at served icons", %{conn: conn} do
      manifest = conn |> get(~p"/site.webmanifest") |> response(200) |> Jason.decode!()

      assert manifest["name"] == "Dockd"

      for %{"src" => src} <- manifest["icons"] do
        assert conn |> get(src) |> response(200) != ""
      end
    end
  end

  describe "digested static files (mix phx.digest)" do
    setup %{conn: conn} do
      output = Path.join(System.tmp_dir!(), "dockd-digest-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(output) end)
      Phoenix.Digester.compile(Application.app_dir(:dockd, "priv/static"), output, true)

      %{"latest" => latest} =
        output |> Path.join("cache_manifest.json") |> File.read!() |> Jason.decode!()

      plug =
        Plug.Static.init(
          at: "/",
          from: output,
          only: DockdWeb.static_paths(),
          only_matching: DockdWeb.static_prefixes()
        )

      links =
        conn
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query(
          ~s|link[rel="icon"], link[rel="apple-touch-icon"], link[rel="manifest"]|
        )
        |> LazyHTML.attribute("href")

      %{latest: latest, plug: plug, links: links}
    end

    test "every icon and the manifest the layout links answer 200 under their digested name",
         %{latest: latest, plug: plug, links: links} do
      expected = %{
        "/favicon.ico" => "image/",
        "/favicon.svg" => "image/svg+xml",
        "/apple-touch-icon.png" => "image/png",
        "/site.webmanifest" => "application/"
      }

      assert Enum.sort(links) == Enum.sort(Map.keys(expected))

      for link <- links do
        digested = "/" <> Map.fetch!(latest, String.trim_leading(link, "/"))
        assert digested =~ ~r/-[0-9a-f]{32}\./

        conn = Plug.Static.call(Plug.Test.conn(:get, digested), plug)

        assert conn.status == 200, "#{digested} answered #{inspect(conn.status)}"
        assert [type] = Plug.Conn.get_resp_header(conn, "content-type")
        assert type =~ expected[link]
      end
    end

    test "the manifest icons keep working, and unrelated root files stay closed", %{plug: plug} do
      File.write!(Path.join(Application.app_dir(:dockd, "priv/static"), "secret-test.txt"), "x")

      on_exit(fn ->
        File.rm(Path.join(Application.app_dir(:dockd, "priv/static"), "secret-test.txt"))
      end)

      assert Plug.Static.call(Plug.Test.conn(:get, "/icon-192.png"), plug).status == 200
      refute Plug.Static.call(Plug.Test.conn(:get, "/secret-test.txt"), plug).halted
    end
  end
end
