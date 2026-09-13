defmodule DockdWeb.ReleaseController do
  use DockdWeb, :controller
  alias Dockd.Catalog

  def index(conn, %{"game_id" => game_id}),
    do: json(conn, %{data: Enum.map(Catalog.list_releases(game_id), &release_json/1)})

  def show(conn, %{"game_id" => game_id, "id" => id}),
    do: json(conn, %{data: release_json(Catalog.get_release!(game_id, id))})

  def create(conn, %{"game_id" => game_id, "release" => attrs}) do
    case Catalog.create_release(game_id, attrs) do
      {:ok, release} -> conn |> put_status(:created) |> json(%{data: release_json(release)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def update(conn, %{"game_id" => game_id, "id" => id, "release" => attrs}) do
    case Catalog.update_release(Catalog.get_release!(game_id, id), attrs) do
      {:ok, release} -> json(conn, %{data: release_json(release)})
      {:error, changeset} -> validation_error(conn, changeset)
    end
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
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{type: "validation", details: errors}})
  end
end
