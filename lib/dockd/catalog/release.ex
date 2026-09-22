defmodule Dockd.Catalog.Release do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "releases" do
    field :platform, Ecto.Enum, values: [:switch, :switch_2]
    field :edition, :string
    field :release_date, :date

    field :release_date_precision, Ecto.Enum,
      values: [:day, :month, :quarter, :year, :tbd],
      default: :tbd

    field :physical_available, :boolean, default: false
    field :digital_available, :boolean, default: false
    field :physical_is_key_card, :boolean
    belongs_to :game, Dockd.Catalog.Game, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(release, attrs) do
    release
    |> cast(attrs, [
      :platform,
      :edition,
      :release_date,
      :release_date_precision,
      :physical_available,
      :digital_available,
      :physical_is_key_card
    ])
    |> put_default_date_precision()
    |> validate_required([:platform, :game_id])
    |> assoc_constraint(:game)
    |> unique_constraint([:game_id, :platform, :edition])
  end

  defp put_default_date_precision(changeset) do
    if get_change(changeset, :release_date_precision) == nil do
      precision = if get_field(changeset, :release_date), do: :day, else: :tbd
      put_change(changeset, :release_date_precision, precision)
    else
      changeset
    end
  end
end
