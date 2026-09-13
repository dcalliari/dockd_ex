defmodule Dockd.Catalog.Release do
  use Ecto.Schema
  import Ecto.Changeset

  schema "releases" do
    field :platform, Ecto.Enum, values: [:switch, :switch_2]
    field :edition, :string
    field :release_date, :date
    field :physical_available, :boolean, default: false
    field :digital_available, :boolean, default: false
    field :physical_is_key_card, :boolean
    belongs_to :game, Dockd.Catalog.Game
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(release, attrs) do
    release
    |> cast(attrs, [:platform, :edition, :release_date, :physical_available, :digital_available])
    |> validate_required([:platform, :game_id])
    |> assoc_constraint(:game)
    |> unique_constraint([:game_id, :platform, :edition])
  end
end
