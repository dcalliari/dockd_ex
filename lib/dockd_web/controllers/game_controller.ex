defmodule DockdWeb.GameController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Dockd.Catalog
  alias DockdWeb.ApiSchemas

  plug OpenApiSpex.Plug.CastAndValidate, render_error: DockdWeb.ApiErrorRenderer

  operation(:index,
    summary: "List games",
    responses: %{
      200 => {"Games", "application/json", ApiSchemas.GameListResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:show,
    summary: "Show a game",
    parameters: [id: [in: :path, required: true, type: :string]],
    responses: %{
      200 => {"Game", "application/json", ApiSchemas.GameResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:create,
    summary: "Create a game",
    request_body:
      {"Game attributes", "application/json", ApiSchemas.GameRequest, [required: true]},
    responses: %{
      201 => {"Game", "application/json", ApiSchemas.GameResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:update,
    summary: "Update a game",
    parameters: [id: [in: :path, required: true, type: :string]],
    request_body:
      {"Game attributes", "application/json", ApiSchemas.GameRequest, [required: true]},
    responses: %{
      200 => {"Game", "application/json", ApiSchemas.GameResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  def index(conn, _params), do: json(conn, %{data: Enum.map(Catalog.list_games(), &game_json/1)})
  def show(conn, params), do: render_game(conn, Catalog.get_game!(path_param(params, :id)))

  def create(conn, _params) do
    case Catalog.create_game(body_attrs(conn, "game")) do
      {:ok, game} -> conn |> put_status(:created) |> render_game(Catalog.get_game!(game.id))
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def update(conn, params) do
    id = path_param(params, :id)

    case Catalog.update_game(Catalog.get_game!(id), body_attrs(conn, "game")) do
      {:ok, game} -> render_game(conn, Catalog.get_game!(game.id))
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  defp path_param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp body_attrs(conn, key) do
    attrs = Map.get(conn.body_params, key, Map.get(conn.body_params, :game, %{}))
    attrs = if is_struct(attrs), do: Map.from_struct(attrs), else: attrs
    Map.reject(attrs, fn {_key, value} -> is_nil(value) end)
  end

  defp render_game(conn, game), do: json(conn, %{data: game_json(game)})

  defp game_json(game) do
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
      estimated_duration_minutes: game.estimated_duration_minutes,
      pace: game.pace,
      play_mode: game.play_mode,
      releases: Enum.map(game.releases || [], &release_json/1)
    }
  end

  defp release_json(release) do
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

  defp validation_error(conn, changeset) do
    details =
      if is_struct(changeset),
        do: Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end),
        else: %{base: [changeset]}

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{type: "validation", details: details}})
  end
end
