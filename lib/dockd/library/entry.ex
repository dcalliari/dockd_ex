defmodule Dockd.Library.Entry do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "entries" do
    field :purchase_intent, Ecto.Enum, values: [:none, :interested, :want, :planned, :preordered]
    field :play_state, Ecto.Enum, values: [:unplayed, :playing, :paused, :finished, :abandoned]
    field :backlog, Ecto.Enum, values: [:no, :backlog, :active]
    field :priority, Ecto.Enum, values: [:low, :normal, :high]

    field :media_preference, Ecto.Enum,
      values: [:physical, :digital, :physical_preferred, :digital_preferred, :either]

    field :target_price_cents, :integer
    field :currency, :string, default: "BRL"
    field :owned_elsewhere, :boolean, default: false
    field :owned_elsewhere_note, :string
    field :duration_override_minutes, :integer
    field :pace_override, Ecto.Enum, values: [:relaxing, :normal, :demanding]
    field :notes, :string
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    belongs_to :game, Dockd.Catalog.Game, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs),
    do:
      entry
      |> cast(attrs, [
        :user_id,
        :game_id,
        :purchase_intent,
        :play_state,
        :backlog,
        :priority,
        :media_preference,
        :target_price_cents,
        :currency,
        :owned_elsewhere,
        :owned_elsewhere_note,
        :duration_override_minutes,
        :pace_override,
        :notes
      ])
      |> validate_required([:user_id, :game_id])
      |> validate_number(:target_price_cents, greater_than_or_equal_to: 0)
end
