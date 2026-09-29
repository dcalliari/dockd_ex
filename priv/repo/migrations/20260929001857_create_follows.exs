defmodule Dockd.Repo.Migrations.CreateFollows do
  use Ecto.Migration

  # Following goes one way; two rows in opposite directions make two accounts friends.
  def change do
    create table(:follows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :follower_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :followed_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:follows, [:follower_id, :followed_id])
    create index(:follows, [:followed_id])
    create constraint(:follows, :not_self, check: "follower_id <> followed_id")
  end
end
