defmodule Dockd.Repo.Migrations.AddPreferredReleaseToEntries do
  use Ecto.Migration

  def change do
    alter table(:entries) do
      add :preferred_release_id, references(:releases, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
