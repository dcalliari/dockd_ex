defmodule Dockd.Catalog.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @availability_values [:nintendo_exclusive, :switch2_exclusive, :multiplatform]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "games" do
    field :title, :string
    field :slug, :string
    field :cover_url, :string
    field :igdb_id, :integer
    field :synced_at, :utc_datetime_usec
    field :developer, :string
    field :publisher, :string
    field :availability, Ecto.Enum, values: @availability_values
    field :other_platforms, {:array, :string}, default: []
    field :estimated_duration_minutes, :integer
    field :pace, Ecto.Enum, values: [:relaxing, :normal, :demanding]
    field :play_mode, Ecto.Enum, values: [:solo, :multi, :both]
    field :alternative_names, {:array, :string}, default: []
    field :search_text, :string, default: ""
    field :rating_count, :integer
    field :hypes, :integer
    has_many :releases, Dockd.Catalog.Release
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :title,
      :slug,
      :cover_url,
      :igdb_id,
      :synced_at,
      :developer,
      :publisher,
      :availability,
      :other_platforms,
      :estimated_duration_minutes,
      :pace,
      :play_mode,
      :alternative_names,
      :rating_count,
      :hypes
    ])
    |> validate_required([:title, :availability])
    |> put_slug()
    |> put_search_text()
    |> validate_length(:title, min: 1)
    |> validate_number(:estimated_duration_minutes, greater_than: 0)
    |> validate_other_platforms()
    |> unique_constraint(:slug)
    |> unique_constraint(:igdb_id)
  end

  # A slug given is kept; otherwise the title gives one when it is new or changes, never
  # on an update that leaves it alone (an IGDB slug such as "trials-of-mana--1" stays).
  defp put_slug(changeset) do
    slug = get_field(changeset, :slug)
    title = get_change(changeset, :title) || (slug in [nil, ""] && get_field(changeset, :title))

    cond do
      is_binary(get_change(changeset, :slug)) and get_change(changeset, :slug) != "" -> changeset
      is_binary(title) -> put_change(changeset, :slug, slugify(title))
      true -> changeset
    end
  end

  # The title and alternative names as the catalog search compares them (`fold/1`),
  # kept apart so a query never matches across two names.
  defp put_search_text(changeset) do
    names = [get_field(changeset, :title) | get_field(changeset, :alternative_names) || []]
    text = names |> Enum.filter(&is_binary/1) |> Enum.map_join("|", &fold/1)
    put_change(changeset, :search_text, text)
  end

  @doc "Folds a text for the catalog search: lower case, only letters and digits."
  def fold(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
  end

  @doc "The slug a title gives when none is given."
  def slugify(title) do
    title
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp validate_other_platforms(changeset) do
    availability = get_field(changeset, :availability)
    platforms = get_field(changeset, :other_platforms) || []

    if availability == :multiplatform do
      changeset
    else
      if platforms == [] do
        changeset
      else
        add_error(changeset, :other_platforms, "deve ficar vazio para obras exclusivas")
      end
    end
  end
end
