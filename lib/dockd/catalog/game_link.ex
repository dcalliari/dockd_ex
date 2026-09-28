defmodule Dockd.Catalog.GameLink do
  @moduledoc """
  Another IGDB entry that is the same game: an edition (`:version`), the Nintendo
  Switch 2 Edition, or a game merged into this one. An entry belongs to at most one
  game.

  `match` says who decided: `:auto` from a safe IGDB signal, `:confirmed` by a person,
  `:review` while a remaster, expanded game or port waits for someone to say whether
  it is the same game, `:rejected` when it is another game and is not asked again.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:version, :switch_2_edition, :expanded, :port, :remaster, :merged]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "game_links" do
    field :igdb_id, :integer
    field :kind, Ecto.Enum, values: @kinds
    field :match, Ecto.Enum, values: [:auto, :confirmed, :review, :rejected]
    belongs_to :game, Dockd.Catalog.Game, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The matches that make the entry this game."
  def accepted, do: [:auto, :confirmed]

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:igdb_id, :game_id, :kind, :match])
    |> validate_required([:igdb_id, :game_id, :kind, :match])
    |> assoc_constraint(:game)
    |> unique_constraint(:igdb_id)
  end
end
