defmodule Dockd.Catalog do
  import Ecto.Query
  alias Dockd.Catalog.{Game, Release}
  alias Dockd.Repo

  def list_games do
    Repo.all(from game in Game, order_by: [asc: game.title], preload: [:releases])
  end

  def get_game!(id), do: Repo.get!(Game, id) |> Repo.preload(:releases)

  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def update_game(%Game{} = game, attrs) do
    game |> Game.changeset(attrs) |> Repo.update()
  end

  def list_releases(game_id),
    do:
      Repo.all(
        from release in Release,
          where: release.game_id == ^game_id,
          order_by: [asc: release.platform]
      )

  def get_release!(game_id, id), do: Repo.get_by!(Release, id: id, game_id: game_id)

  def create_release(game_id, attrs) do
    game = Repo.get!(Game, game_id)

    %Release{game: game, game_id: game.id}
    |> Release.changeset(attrs)
    |> Repo.insert()
  end

  def update_release(%Release{} = release, attrs) do
    release |> Release.changeset(attrs) |> Repo.update()
  end
end
