defmodule Dockd.Repo.Migrations.AddIgdbFieldsToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :igdb_id, :integer
      add :synced_at, :utc_datetime_usec
    end

    create unique_index(:games, [:igdb_id], where: "igdb_id IS NOT NULL")
  end
end
