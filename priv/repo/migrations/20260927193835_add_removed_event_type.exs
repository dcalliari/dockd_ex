defmodule Dockd.Repo.Migrations.AddRemovedEventType do
  use Ecto.Migration

  # ADD VALUE cannot run inside a transaction before PostgreSQL 12.
  @disable_ddl_transaction true

  def up, do: execute("ALTER TYPE event_type ADD VALUE IF NOT EXISTS 'removed'")

  # PostgreSQL cannot drop a value from an enum; the unused value is harmless.
  def down, do: :ok
end
