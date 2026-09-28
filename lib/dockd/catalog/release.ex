defmodule Dockd.Catalog.Release do
  use Ecto.Schema
  import Ecto.Changeset

  @standard "Edição padrão"

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "releases" do
    field :platform, Ecto.Enum, values: [:switch, :switch_2]
    field :edition, :string, default: @standard
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

  @doc """
  The edition of a platform's base release, the one IGDB creates. Every other edition
  is a release the store sells under its own name.
  """
  def standard_edition, do: @standard

  @doc "Whether a release is the platform's standard edition."
  def standard?(%__MODULE__{edition: edition}), do: edition in [nil, "", @standard]

  @doc """
  The media a release is sold in, physical first. A release that declares neither is
  treated as digital, so every release can be bought and priced.
  """
  def media(%__MODULE__{} = release) do
    case Enum.filter(
           [physical: release.physical_available, digital: release.digital_available],
           &elem(&1, 1)
         ) do
      [] -> [:digital]
      media -> Keyword.keys(media)
    end
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
    |> put_standard_edition()
    |> validate_required([:platform, :game_id])
    |> assoc_constraint(:game)
    |> unique_constraint([:game_id, :platform, :edition])
  end

  defp put_standard_edition(changeset) do
    case get_field(changeset, :edition) do
      edition when edition in [nil, ""] -> put_change(changeset, :edition, @standard)
      edition -> put_change(changeset, :edition, String.trim(edition))
    end
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
