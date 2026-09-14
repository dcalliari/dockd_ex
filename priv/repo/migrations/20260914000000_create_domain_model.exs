defmodule Dockd.Repo.Migrations.CreateDomainModel do
  use Ecto.Migration

  @enums %{
    entry_purchase_intent: ~w(none interested want planned preordered),
    entry_play_state: ~w(unplayed playing paused finished abandoned),
    entry_backlog: ~w(no backlog active),
    entry_priority: ~w(low normal high),
    entry_media_preference: ~w(physical digital physical_preferred digital_preferred either),
    entry_pace: ~w(relaxing normal demanding),
    ownership_type: ~w(physical digital subscription shared borrowed),
    purchase_format: ~w(physical digital),
    price_format: ~w(physical digital),
    store: ~w(eshop),
    event_type: ~w(added intent_changed purchased started paused resumed finished abandoned backlogged activated vetoed)
  }

  def change do
    for {name, values} <- @enums do
      execute "CREATE TYPE #{name} AS ENUM (#{Enum.map_join(values, ", ", &quote/1)})",
              "DROP TYPE #{name}"
    end

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :purchase_intent, :entry_purchase_intent, null: false, default: "none"
      add :play_state, :entry_play_state, null: false, default: "unplayed"
      add :backlog, :entry_backlog, null: false, default: "no"
      add :priority, :entry_priority, null: false, default: "normal"
      add :media_preference, :entry_media_preference, null: false, default: "either"
      add :target_price_cents, :integer
      add :currency, :text, null: false, default: "BRL"
      add :owned_elsewhere, :boolean, null: false, default: false
      add :owned_elsewhere_note, :text
      add :duration_override_minutes, :integer
      add :pace_override, :entry_pace
      add :notes, :text
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:entries, [:user_id, :game_id])
    create index(:entries, [:user_id])

    create table(:purchases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :release_id, references(:releases, type: :binary_id, on_delete: :delete_all), null: false
      add :format, :purchase_format, null: false
      add :price_cents, :integer, null: false
      add :currency, :text, null: false, default: "BRL"
      add :store_credit_used_cents, :integer, null: false, default: 0
      add :purchased_at, :utc_datetime_usec, null: false
      add :is_preorder, :boolean, null: false, default: false
      add :retailer, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end
    create index(:purchases, [:user_id, :release_id])

    create table(:ownerships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :release_id, references(:releases, type: :binary_id, on_delete: :delete_all), null: false
      add :ownership_type, :ownership_type, null: false
      add :acquired_at, :utc_datetime_usec, null: false
      add :purchase_id, references(:purchases, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:ownerships, [:user_id, :release_id, :ownership_type])

    create table(:release_vetoes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :release_id, references(:releases, type: :binary_id, on_delete: :delete_all), null: false
      add :reason, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
    create unique_index(:release_vetoes, [:user_id, :release_id])

    create table(:price_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :release_id, references(:releases, type: :binary_id, on_delete: :delete_all), null: false
      add :format, :price_format, null: false
      add :price_cents, :integer, null: false
      add :currency, :text, null: false, default: "BRL"
      add :observed_at, :utc_datetime_usec, null: false
      add :source, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end
    create index(:price_observations, [:user_id, :release_id])

    create table(:store_balances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :store, :store, null: false
      add :amount_cents, :integer, null: false
      add :currency, :text, null: false, default: "BRL"
      timestamps(type: :utc_datetime_usec)
    end
    create unique_index(:store_balances, [:user_id, :store])

    create table(:balance_reservations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :store, :store, null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :amount_cents, :integer, null: false
      add :note, :text
      timestamps(type: :utc_datetime_usec)
    end

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :nilify_all)
      add :release_id, references(:releases, type: :binary_id, on_delete: :nilify_all)
      add :type, :event_type, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :payload, :map, null: false, default: %{}
    end
    create index(:events, [:user_id, :occurred_at])
  end

  defp quote(value), do: "'#{value}'"
end
