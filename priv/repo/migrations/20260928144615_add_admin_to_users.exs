defmodule Dockd.Repo.Migrations.AddAdminToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :admin, :boolean, null: false, default: false
    end

    execute "UPDATE users SET admin = TRUE WHERE email = 'admin@dpe.dev'"
  end

  def down do
    alter table(:users) do
      remove :admin
    end
  end
end
