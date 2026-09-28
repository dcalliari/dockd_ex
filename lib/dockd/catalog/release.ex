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
    field :eshop_searched_at, :utc_datetime_usec
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

  @doc """
  Whether a release is out by `today`: `:released`, `:upcoming` (dated, not out yet) or
  `:undated`. A date known only by month, quarter or year is out once that whole period
  is over. The eShop sales status, when the store sells the release, holds it back:
  `unreleased` and `preorder` are never out, whatever the date says. Without a date,
  a release the store sells or sold is out.
  """
  def launch(%__MODULE__{release_date: date} = release, today, sales_status \\ nil) do
    cond do
      sales_status in ["unreleased", "preorder"] -> if date, do: :upcoming, else: :undated
      date && out_by?(release, today) -> :released
      date -> :upcoming
      sales_status in ["onsale", "sales_termination"] -> :released
      true -> :undated
    end
  end

  defp out_by?(%{release_date_precision: :tbd}, _today), do: false

  defp out_by?(%{release_date: date, release_date_precision: precision}, today),
    do: Date.compare(period_end(date, precision), today) != :gt

  defp period_end(date, :year), do: Date.new!(date.year, 12, 31)
  defp period_end(date, :month), do: Date.end_of_month(date)

  defp period_end(date, :quarter),
    do: date |> Date.beginning_of_month() |> Date.shift(month: 2) |> Date.end_of_month()

  defp period_end(date, _day), do: date

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

  # Only when no precision was given: IGDB repeating the one stored is not a change, and
  # must not turn a year into a day.
  defp put_default_date_precision(changeset) do
    if changeset.params["release_date_precision"] in [nil, ""] and
         Map.has_key?(changeset.changes, :release_date) do
      precision = if get_field(changeset, :release_date), do: :day, else: :tbd
      put_change(changeset, :release_date_precision, precision)
    else
      changeset
    end
  end
end
