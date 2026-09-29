defmodule Dockd.Repo.Migrations.CreateProfileFavorites do
  use Ecto.Migration

  def change do
    create table(:profile_favorites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:profile_favorites, [:user_id, :game_id])
    create unique_index(:profile_favorites, [:user_id, :position])
  end
end
