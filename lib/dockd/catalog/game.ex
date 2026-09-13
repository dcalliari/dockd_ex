defmodule Dockd.Catalog.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @availability_values [:nintendo_exclusive, :switch2_exclusive, :multiplatform]

  schema "games" do
    field :title, :string
    field :slug, :string
    field :cover_url, :string
    field :developer, :string
    field :publisher, :string
    field :availability, Ecto.Enum, values: @availability_values
    field :other_platforms, {:array, :string}, default: []
    field :estimated_duration_minutes, :integer
    field :pace, Ecto.Enum, values: [:relaxing, :normal, :demanding]
    field :play_mode, Ecto.Enum, values: [:solo, :multi, :both]
    has_many :releases, Dockd.Catalog.Release
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :title,
      :slug,
      :cover_url,
      :developer,
      :publisher,
      :availability,
      :other_platforms,
      :estimated_duration_minutes,
      :pace,
      :play_mode
    ])
    |> validate_required([:title, :availability])
    |> put_slug()
    |> validate_length(:title, min: 1)
    |> validate_number(:estimated_duration_minutes, greater_than: 0)
    |> validate_other_platforms()
    |> unique_constraint(:slug)
  end

  defp put_slug(changeset) do
    case get_change(changeset, :slug) do
      slug when is_binary(slug) and byte_size(slug) > 0 ->
        changeset

      _ ->
        case get_change(changeset, :title) || get_field(changeset, :title) do
          title when is_binary(title) -> put_change(changeset, :slug, slugify(title))
          _ -> changeset
        end
    end
  end

  defp slugify(title) do
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
