defmodule Dockd.Repo.Migrations.AddGameLinksAndEditions do
  use Ecto.Migration

  # An edition is one more release of the same game (platform and edition), so the
  # standard one needs a name the unique index can compare: NULL never collides.
  def change do
    execute "UPDATE releases SET edition = 'Edição padrão' WHERE edition IS NULL OR edition = ''",
            ""

    alter table(:releases) do
      modify :edition, :text,
        null: false,
        default: "Edição padrão",
        from: {:text, null: true, default: nil}
    end

    execute """
            CREATE TYPE game_link_kind AS ENUM
              ('version', 'switch_2_edition', 'expanded', 'port', 'remaster', 'merged')
            """,
            "DROP TYPE game_link_kind"

    # The other IGDB entries that are this game, and the ones waiting for a person to
    # say whether they are. match reuses the store listing's values.
    create table(:game_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :igdb_id, :integer, null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :game_link_kind, null: false
      add :match, :listing_match, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:game_links, [:igdb_id])
    create index(:game_links, [:game_id])

    # When the store's product family (editions, Switch 2 Edition) was read, once.
    alter table(:store_listings) do
      add :family_read_at, :utc_datetime_usec
    end
  end
end
