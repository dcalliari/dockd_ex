defmodule Dockd.Repo.Migrations.AddCatalogCuration do
  use Ecto.Migration
  import Ecto.Query

  # The catalog is loaded from IGDB by a criterion (Dockd.Catalog.Curation) and searched
  # locally: the game keeps what the search compares (title and IGDB alternative names,
  # without accents or punctuation) and what orders it (IGDB rating count and hypes).
  def up do
    alter table(:games) do
      add :alternative_names, {:array, :text}, null: false, default: []
      add :search_text, :text, null: false, default: ""
      add :rating_count, :integer
      add :hypes, :integer
    end

    # When the eShop search last looked for a release that it did not find, so a game
    # nobody follows is searched again weekly, not daily.
    alter table(:releases) do
      add :eshop_searched_at, :utc_datetime_usec
    end

    flush()

    for {id, title} <- repo().all(from(g in "games", select: {g.id, g.title})) do
      repo().update_all(from(g in "games", where: g.id == ^id), set: [search_text: fold(title)])
    end
  end

  def down do
    alter table(:releases) do
      remove :eshop_searched_at
    end

    alter table(:games) do
      remove :alternative_names
      remove :search_text
      remove :rating_count
      remove :hypes
    end
  end

  # The same folding as Dockd.Catalog.Game at the time of this migration.
  defp fold(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
  end
end
