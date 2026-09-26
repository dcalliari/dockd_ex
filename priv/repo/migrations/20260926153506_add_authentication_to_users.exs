defmodule Dockd.Repo.Migrations.AddAuthenticationToUsers do
  use Ecto.Migration

  # The existing users keep their rows and every library record pointing at them.
  # Email stays nullable because the owner row predates accounts: it receives an
  # email and a password through Dockd.Release.claim_owner/2 after deploy.
  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    alter table(:users) do
      add :email, :citext
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
    end

    create unique_index(:users, [:email])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
