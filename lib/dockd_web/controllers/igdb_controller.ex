defmodule DockdWeb.IGDBController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Dockd.{Catalog, IGDB}
  alias DockdWeb.ApiSchemas
  plug OpenApiSpex.Plug.CastAndValidate, render_error: DockdWeb.ApiErrorRenderer

  operation(:search,
    summary: "Search IGDB",
    parameters: [q: [in: :query, required: true, type: :string]],
    responses: %{
      200 => {"Results", "application/json", ApiSchemas.IGDBSearchResponse},
      503 => {"Not configured", "application/json", ApiSchemas.IGDBError}
    }
  )

  def search(conn, %{q: query}) do
    case IGDB.search(query) do
      {:ok, %{body: body}} ->
        json(conn, %{data: body})

      {:error, :authentication_failed} ->
        not_configured(conn)

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: %{type: "igdb", details: inspect(reason)}})
    end
  end

  operation(:import,
    summary: "Import an IGDB game",
    parameters: [igdb_id: [in: :path, required: true, type: :integer]],
    responses: %{
      201 => {"Game", "application/json", ApiSchemas.GameResponse},
      404 => {"Not found", "application/json", ApiSchemas.IGDBError},
      503 => {"Not configured", "application/json", ApiSchemas.IGDBError}
    }
  )

  def import(conn, %{igdb_id: id}) do
    with true <- IGDB.configured?(),
         {:ok, %{body: [data]}} <- IGDB.get_games([id]),
         {:ok, game} <- Catalog.create_game(import_attrs(data)),
         :ok <- import_releases(game, data) do
      conn
      |> put_status(:created)
      |> json(%{data: %{id: game.id, igdb_id: game.igdb_id, title: game.title}})
    else
      false ->
        not_configured(conn)

      {:ok, %{body: []}} ->
        conn |> put_status(:not_found) |> json(%{error: %{type: "not_found"}})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: %{
            type: "validation",
            details: Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end)
          }
        })

      _ ->
        not_configured(conn)
    end
  end

  operation(:sync,
    summary: "Synchronize linked games from IGDB",
    responses: %{
      200 => {"Sync result", "application/json", ApiSchemas.IGDBSyncResponse},
      503 => {"Not configured", "application/json", ApiSchemas.IGDBError}
    }
  )

  def sync(conn, _params) do
    case Catalog.sync_igdb() do
      {:ok, result} -> json(conn, %{data: result})
      {:error, :not_configured} -> not_configured(conn)
    end
  end

  operation(:match,
    summary: "Match local games to IGDB",
    parameters: [dry_run: [in: :query, required: false, type: :boolean]],
    responses: %{
      200 => {"Match result", "application/json", ApiSchemas.IGDBMatchResponse},
      503 => {"Not configured", "application/json", ApiSchemas.IGDBError}
    }
  )

  def match(conn, params) do
    dry_run = Map.get(params, :dry_run, false)

    case Catalog.match_igdb(dry_run: dry_run) do
      {:error, :not_configured} -> not_configured(conn)
      result -> json(conn, %{data: result})
    end
  end

  defp import_attrs(data) do
    %{
      title: data["name"],
      igdb_id: data["id"],
      availability: :multiplatform,
      cover_url: cover_url(data),
      developer: company(data, "developer"),
      publisher: company(data, "publisher")
    }
  end

  defp import_releases(game, data) do
    Enum.each([{:switch, 130}, {:switch_2, 508}], fn {platform, id} ->
      case Enum.find(data["release_dates"] || [], &(&1["platform"] == id)) do
        %{"date" => date} ->
          Catalog.create_release(game.id, %{
            platform: platform,
            release_date: DateTime.from_unix!(date) |> DateTime.to_date()
          })

        _ ->
          :ok
      end
    end)

    :ok
  end

  defp cover_url(%{"cover" => %{"image_id" => id}}),
    do: "https://images.igdb.com/igdb/image/upload/t_cover_big/#{id}.jpg"

  defp cover_url(_), do: nil

  defp company(data, role),
    do:
      (data["involved_companies"] || [])
      |> Enum.find_value(fn c -> if c[role], do: get_in(c, ["company", "name"]) end)

  defp not_configured(conn),
    do:
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: %{type: "not_configured", details: "IGDB is not configured"}})
end
