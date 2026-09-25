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

      {:error, reason} when reason in [:authentication_failed, :not_configured] ->
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
    case Catalog.import_igdb(id) do
      {:ok, game} ->
        conn
        |> put_status(:created)
        |> json(%{data: imported_game_json(game)})

      {:error, :not_configured} ->
        not_configured(conn)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: %{type: "not_found"}})

      {:error, %Ecto.Changeset{} = changeset} ->
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
      {:ok, result} -> json(conn, %{data: sync_json(result)})
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

  defp sync_json(%{synced: synced, results: results}),
    do: %{synced: synced, results: Enum.map(results, &sync_result_json/1)}

  defp sync_result_json({:ok, result}), do: %{status: "ok", data: result}

  defp sync_result_json({:error, {game_id, reason}}),
    do: %{status: "error", game_id: game_id, reason: inspect(reason)}

  defp imported_game_json(game) do
    %{
      id: game.id,
      title: game.title,
      slug: game.slug,
      cover_url: game.cover_url,
      igdb_id: game.igdb_id,
      synced_at: game.synced_at,
      developer: game.developer,
      publisher: game.publisher,
      availability: game.availability,
      other_platforms: game.other_platforms,
      releases: Enum.map(game.releases || [], &imported_release_json/1)
    }
  end

  defp imported_release_json(release) do
    %{
      id: release.id,
      game_id: release.game_id,
      platform: release.platform,
      edition: release.edition,
      release_date: release.release_date,
      release_date_precision: release.release_date_precision,
      physical_available: release.physical_available,
      digital_available: release.digital_available
    }
  end

  defp not_configured(conn),
    do:
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: %{type: "not_configured", details: "IGDB is not configured"}})
end
