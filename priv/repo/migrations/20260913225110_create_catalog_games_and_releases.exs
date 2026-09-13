defmodule Dockd.Repo.Migrations.CreateCatalogGamesAndReleases do
  use Ecto.Migration

  def change do
    create enum(:game_availability, [:nintendo_exclusive, :switch2_exclusive, :multiplatform])
    create enum(:game_pace, [:relaxing, :normal, :demanding])
    create enum(:game_play_mode, [:solo, :multi, :both])
    create enum(:release_platform, [:switch, :switch_2])

    create table(:games) do
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

    create table(:releases) do
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
