defmodule Dockd.Repo.Migrations.AddProfileToUsers do
  use Ecto.Migration

  # The public profile lives at /u/:username. The name in the address comes from the
  # email, as Dockd.Accounts.User does for a new account, so nobody fills a new field.
  # The owner row that predates accounts has no email and gets its username when claimed.
  def up do
    alter table(:users) do
      add :username, :citext
      add :profile_visibility, :string, null: false, default: "public"
    end

    create unique_index(:users, [:username])

    create constraint(:users, :profile_visibility_known,
             check: "profile_visibility IN ('public', 'friends')"
           )

    execute """
    WITH base AS (
      SELECT id, inserted_at,
             COALESCE(NULLIF(LEFT(regexp_replace(
               translate(lower(split_part(email::text, '@', 1)),
                         'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
               '[^a-z0-9]', '', 'g'), 30), ''), 'conta') AS name
        FROM users
       WHERE email IS NOT NULL
    ), numbered AS (
      SELECT id, name, row_number() OVER (PARTITION BY name ORDER BY inserted_at, id) AS n
        FROM base
    )
    UPDATE users
       SET username = CASE WHEN numbered.n = 1 THEN numbered.name ELSE numbered.name || numbered.n END
      FROM numbered
     WHERE numbered.id = users.id
    """
  end

  def down do
    alter table(:users) do
      remove :username
      remove :profile_visibility
    end
  end
end
