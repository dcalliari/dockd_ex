defmodule DockdWeb.GameController do
  use DockdWeb, :controller
  alias Dockd.Catalog

  def index(conn, _params), do: json(conn, %{data: Enum.map(Catalog.list_games(), &game_json/1)})
  def show(conn, %{"id" => id}), do: render_game(conn, Catalog.get_game!(id))

  def create(conn, %{"game" => attrs}) do
    case Catalog.create_game(attrs) do
      {:ok, game} -> conn |> put_status(:created) |> render_game(Catalog.get_game!(game.id))
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def create(conn, _), do: validation_error(conn, "game is required")

  def update(conn, %{"id" => id, "game" => attrs}) do
    case Catalog.update_game(Catalog.get_game!(id), attrs) do
      {:ok, game} -> render_game(conn, Catalog.get_game!(game.id))
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  defp render_game(conn, game), do: json(conn, %{data: game_json(game)})

  defp game_json(game) do
    %{
      id: game.id,
      title: game.title,
      slug: game.slug,
      cover_url: game.cover_url,
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
      platform: release.platform,
      edition: release.edition,
      release_date: release.release_date,
      physical_available: release.physical_available,
      digital_available: release.digital_available
    }
  end

  defp validation_error(conn, changeset) do
    errors =
      if is_struct(changeset),
        do: Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end),
        else: %{base: [changeset]}

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{type: "validation", details: errors}})
  end
end
