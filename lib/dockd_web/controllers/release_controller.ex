defmodule DockdWeb.ReleaseController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Dockd.Catalog
  alias DockdWeb.ApiSchemas

  plug OpenApiSpex.Plug.CastAndValidate, render_error: DockdWeb.ApiErrorRenderer

  operation(:index,
    summary: "List releases for a game",
    parameters: [game_id: [in: :path, required: true, type: :string]],
    responses: %{
      200 => {"Releases", "application/json", ApiSchemas.ReleaseListResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:show,
    summary: "Show a release",
    parameters: [
      game_id: [in: :path, required: true, type: :string],
      id: [in: :path, required: true, type: :string]
    ],
    responses: %{
      200 => {"Release", "application/json", ApiSchemas.ReleaseResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:create,
    summary: "Create a release",
    parameters: [game_id: [in: :path, required: true, type: :string]],
    request_body:
      {"Release attributes", "application/json", ApiSchemas.ReleaseRequest, [required: true]},
    responses: %{
      201 => {"Release", "application/json", ApiSchemas.ReleaseResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:update,
    summary: "Update a release",
    parameters: [
      game_id: [in: :path, required: true, type: :string],
      id: [in: :path, required: true, type: :string]
    ],
    request_body:
      {"Release attributes", "application/json", ApiSchemas.ReleaseRequest, [required: true]},
    responses: %{
      200 => {"Release", "application/json", ApiSchemas.ReleaseResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  def index(conn, params),
    do:
      json(conn, %{
        data: Enum.map(Catalog.list_releases(path_param(params, :game_id)), &release_json/1)
      })

  def show(conn, params),
    do:
      json(conn, %{
        data:
          release_json(
            Catalog.get_release!(path_param(params, :game_id), path_param(params, :id))
          )
      })

  def create(conn, params) do
    case Catalog.create_release(path_param(params, :game_id), body_attrs(conn)) do
      {:ok, release} -> conn |> put_status(:created) |> json(%{data: release_json(release)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def update(conn, params) do
    game_id = path_param(params, :game_id)
    id = path_param(params, :id)

    case Catalog.update_release(Catalog.get_release!(game_id, id), body_attrs(conn)) do
      {:ok, release} -> json(conn, %{data: release_json(release)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  defp path_param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp body_attrs(conn) do
    attrs = Map.get(conn.body_params, "release", Map.get(conn.body_params, :release, %{}))
    attrs = if is_struct(attrs), do: Map.from_struct(attrs), else: attrs
    Map.reject(attrs, fn {_key, value} -> is_nil(value) end)
  end

  defp release_json(release) do
    %{
      id: release.id,
      game_id: release.game_id,
      platform: release.platform,
      edition: release.edition,
      release_date: release.release_date,
      physical_available: release.physical_available,
      digital_available: release.digital_available
    }
  end

  defp validation_error(conn, changeset) do
    details = Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{type: "validation", details: details}})
  end
end
