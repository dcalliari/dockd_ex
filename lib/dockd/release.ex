defmodule Dockd.Release do
  @moduledoc false
  @app :dockd

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Gives the library that predates accounts an email and a password. Run once after the
  migration that added accounts: `bin/dockd eval 'Dockd.Release.claim_owner("email", "senha")'`.
  """
  def claim_owner(email, password) do
    with_repo(fn -> Dockd.Accounts.claim_owner(email, password) end)
  end

  @doc ~S"""
  Replaces a forgotten password and ends the account's sessions:
  `bin/dockd eval 'Dockd.Release.reset_password("email", "senha")'`.
  """
  def reset_password(email, password) do
    with_repo(fn -> Dockd.Accounts.reset_password(email, password) end)
  end

  @doc ~S"""
  Prints what joining the catalog's IGDB families does (an edition's game moved to its
  parent, the Switch 2 Edition as a release, duplicates merged, doubtful ones queued),
  without changing anything: `bin/dockd eval 'Dockd.Release.families()'`. The daily
  sync applies it on its own; `families(apply: true)` applies it now.
  """
  def families(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(:req)
    dry_run = not Keyword.get(opts, :apply, false)

    with_repo(fn -> dry_run |> resolve_families() |> print_steps() end)
  end

  defp resolve_families(dry_run), do: Dockd.Catalog.resolve_families(dry_run: dry_run)

  defp print_steps(steps) when is_list(steps) do
    Enum.each(steps, &IO.puts("#{&1.step}\t#{&1.game.title}\t#{&1.igdb_id}\t#{&1.kind}"))
    length(steps)
  end

  defp print_steps(error), do: error

  defp with_repo(fun) do
    load_app()
    [repo] = repos()
    {:ok, result, _} = Ecto.Migrator.with_repo(repo, fn _repo -> fun.() end)
    result
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.load(@app)
  end
end
