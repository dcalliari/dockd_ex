defmodule Dockd.Repo.Migrations.BackfillOwnedElsewhereBeforePosseRule do
  use Ecto.Migration

  # Jogando, Pausado, Zerado and Larguei now require posse (Dockd.Library.set_status/4).
  # Entries written before that rule can be playing/finished/abandoned with no ownership;
  # Dockd.Library.backfill_owned_elsewhere/0 flags them owned_elsewhere instead of
  # guessing a release or media it was never told.
  def up, do: Dockd.Library.backfill_owned_elsewhere()

  # owned_elsewhere on these entries is exactly the fact the rule now requires; there is
  # nothing safe to roll back to.
  def down, do: :ok
end
