defmodule Dockd.Repo.Migrations.AddReleaseDatePrecision do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE release_date_precision AS ENUM ('day', 'month', 'quarter', 'year', 'tbd')"

    alter table(:releases) do
      add :release_date_precision, :release_date_precision, default: "tbd"
    end

    execute "UPDATE releases SET release_date_precision = 'day' WHERE release_date IS NOT NULL"

    alter table(:releases) do
      modify :release_date_precision, :release_date_precision, null: false, default: "tbd"
    end
  end

  def down do
    alter table(:releases) do
      remove :release_date_precision
    end

    execute "DROP TYPE release_date_precision"
  end
end
