defmodule Dockd.Repo.Migrations.CreateCatalogGamesAndReleases do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE game_availability AS ENUM ('nintendo_exclusive', 'switch2_exclusive', 'multiplatform')",
            "DROP TYPE game_availability"

    execute "CREATE TYPE game_pace AS ENUM ('relaxing', 'normal', 'demanding')",
            "DROP TYPE game_pace"

    execute "CREATE TYPE game_play_mode AS ENUM ('solo', 'multi', 'both')",
            "DROP TYPE game_play_mode"

    execute "CREATE TYPE release_platform AS ENUM ('switch', 'switch_2')",
            "DROP TYPE release_platform"

    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :text, null: false
      add :slug, :text, null: false
      add :cover_url, :text
      add :developer, :text
      add :publisher, :text
      add :availability, :game_availability, null: false
      add :other_platforms, {:array, :text}, null: false, default: []
      add :estimated_duration_minutes, :integer
      add :pace, :game_pace
      add :play_mode, :game_play_mode
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:games, [:slug])

    create table(:releases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :platform, :release_platform, null: false
      add :edition, :text
      add :release_date, :date
      add :physical_available, :boolean, null: false, default: false
      add :digital_available, :boolean, null: false, default: false
      add :physical_is_key_card, :boolean
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:releases, [:game_id, :platform, :edition])
    create index(:releases, [:game_id])
  end
end
