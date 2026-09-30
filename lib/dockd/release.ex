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
  Promotes or demotes an account:
  `bin/dockd eval 'Dockd.Release.set_admin("email", true)'`.
  """
  def set_admin(email, admin) when is_boolean(admin) do
    with_repo(fn -> Dockd.Accounts.set_admin(email, admin) end)
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

  @doc ~S"""
  Loads the catalog by its criterion (`Dockd.Catalog.curate/1`), removes the games
  outside it that no account refers to, and prints the report: how many entered, how
  many each rule left out, with the most rated of them. Stops safely at any point; a
  new run, or the daily sync, goes on from there. The daily sync then joins the
  families and finds the eShop products:
  `bin/dockd eval 'Dockd.Release.curate()'`. `curate(prune: false)` only adds.
  """
  def curate(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(:req)
    prune = Keyword.get(opts, :prune, true)

    with_repo(fn ->
      case Dockd.Catalog.curate(prune: prune) do
        {:ok, report} -> print_report(report)
        error -> error
      end
    end)
  end

  @doc ~S"""
  Runs the IGDB catalog synchronization now, including existing releases:
  `bin/dockd eval 'Dockd.Release.sync_catalog()'`. It is safe to repeat.
  """
  def sync_catalog do
    {:ok, _} = Application.ensure_all_started(:req)
    with_repo(fn -> Dockd.Catalog.sync_igdb() end)
  end

  @doc ~S"""
  Confirms physical_available for every release with a physical ownership or a
  physical price observation recorded before the flag was evidence-based. Additive
  only, safe to repeat: `bin/dockd eval 'Dockd.Release.backfill_physical_available()'`.
  """
  def backfill_physical_available do
    with_repo(fn -> Dockd.Catalog.backfill_physical_available() end)
  end

  @reasons [
    status: "cancelado, boato ou fora do ar",
    no_cover: "sem capa",
    publisher: "editora excluída",
    unpopular: "abaixo do critério de popularidade",
    bundle_without_game: "pacote só de conteúdo extra",
    edition_of_other: "edição de outro jogo"
  ]

  defp print_report(report) do
    IO.puts("Entraram pelo critério: #{report.admitted} (#{report.imported} novos)")
    IO.puts("Ranking da eShop: #{inspect(report.eshop)}")

    for {reason, label} <- @reasons,
        %{count: count, sample: sample} <- [report.excluded[reason]] do
      IO.puts("Fora, #{label}: #{count}\n  " <> Enum.join(sample, "\n  "))
    end

    for {type, label} <- Dockd.Catalog.Curation.excluded_game_types(),
        {:ok, count, sample} <- [Dockd.IGDB.catalog_sample(type)] do
      IO.puts("Fora, #{label} (tipo #{type} no IGDB): #{count}\n  " <> Enum.join(sample, "\n  "))
    end

    IO.puts(
      "Fora do critério, mantidos por estarem numa biblioteca: #{Enum.join(report.kept, "; ")}"
    )

    IO.puts("Removidos do catálogo: #{Enum.join(report.pruned, "; ")}")
    IO.puts("Falharam: #{inspect(report.failed)}")
    report
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
