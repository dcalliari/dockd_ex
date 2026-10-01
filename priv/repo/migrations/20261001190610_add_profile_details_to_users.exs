defmodule Dockd.Repo.Migrations.AddProfileDetailsToUsers do
  use Ecto.Migration

  # The public header carries a short bio, a place and one link. All three are optional
  # text the owner writes in Configurações, so existing accounts simply start empty.
  def change do
    alter table(:users) do
      add :bio, :string, size: 140
      add :location, :string, size: 60
      add :link, :string, size: 200
    end
  end
end
