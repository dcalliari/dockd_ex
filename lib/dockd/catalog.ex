defmodule Dockd.Catalog do
  @moduledoc """
  Catalog synchronization and Nintendo release data.

  A release synchronized from IGDB is an eShop release, so it is always marked
  as digitally available. Physical availability remains false unless it was
  already known locally; IGDB does not provide a reliable physical inventory
  signal for the catalog. A standard release on a platform that IGDB does not list for
  the game, nor for the entries joined to it, is dropped by the sync when nothing refers
  to it.
  """
  import Ecto.Query
  require Logger
  alias Dockd.Catalog.{Curation, Game, GameLink, IgdbFamily, Merge, Release}
  alias Dockd.Library.{Entry, Ownership, ReleaseVeto}
  alias Dockd.Pricing.StoreListing
  alias Dockd.Purchasing.{PriceObservation, Purchase}
  alias Dockd.Repo

  def list_games do
    Repo.all(from game in Game, order_by: [asc: game.title], preload: [:releases])
  end

  def get_game!(id), do: Repo.get!(Game, id) |> Repo.preload(:releases)

  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def update_game(%Game{} = game, attrs) do
    game |> Game.changeset(attrs) |> Repo.update()
  end

  def list_releases(game_id),
    do:
      Repo.all(
        from release in Release,
          where: release.game_id == ^game_id,
          order_by: [asc: release.platform]
      )

  def get_release!(game_id, id), do: Repo.get_by!(Release, id: id, game_id: game_id)

  def create_release(game_id, attrs) do
    game = Repo.get!(Game, game_id)

    %Release{game: game, game_id: game.id}
    |> Release.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Marks a release as physically available once evidence exists: a physical price
  observation or a physical ownership record. Idempotent, and never turns the flag
  back off, since evidence does not expire.
  """
  def confirm_physical_available(release_id) do
    Repo.update_all(
      from(r in Release, where: r.id == ^release_id and r.physical_available == false),
      set: [physical_available: true]
    )
  end

  @doc """
  Applies `confirm_physical_available/1` to every release with evidence recorded
  before the flag became evidence-based: a physical ownership or a physical price
  observation. Only turns the flag on, never off, and repeating it changes nothing
  once every release with evidence already has it set. Returns how many it changed.
  """
  def backfill_physical_available do
    release_ids =
      (Repo.all(from o in Ownership, where: o.ownership_type == :physical, select: o.release_id) ++
         Repo.all(from p in PriceObservation, where: p.format == :physical, select: p.release_id))
      |> Enum.uniq()

    Enum.reduce(release_ids, 0, fn release_id, changed ->
      case confirm_physical_available(release_id) do
        {1, _} -> changed + 1
        _ -> changed
      end
    end)
  end

  def update_release(%Release{} = release, attrs) do
    release |> Release.changeset(attrs) |> Repo.update()
  end

  @doc "Deletes a release when no user data refers to it."
  def delete_release(%Release{} = release) do
    case blockers(release) do
      [] -> Repo.delete(release)
      blockers -> {:error, {:in_use, blockers}}
    end
  end

  defp blockers(release) do
    [
      {:ownership, Ownership},
      {:purchase, Purchase},
      {:price_observation, PriceObservation},
      {:veto, ReleaseVeto}
    ]
    |> Enum.filter(fn {_name, schema} ->
      Repo.exists?(from record in schema, where: record.release_id == ^release.id)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Brings every game with an IGDB id up to date: first its family (`resolve_families/1`),
  then its metadata and Nintendo release dates, asked of IGDB in pages of 500 games.
  """
  def sync_igdb do
    if Dockd.IGDB.configured?() do
      family = resolve_families()
      games = Repo.all(from game in Game, where: not is_nil(game.igdb_id), preload: [:releases])
      externals = games |> Enum.map(& &1.igdb_id) |> fetch_externals() |> Map.new(&{&1["id"], &1})
      results = Enum.map(games, &sync_game(&1, externals[&1.igdb_id]))

      {:ok,
       %{synced: Enum.count(results, &match?({:ok, _}, &1)), results: results, family: family}}
    else
      {:error, :not_configured}
    end
  end

  defp sync_game(game, nil), do: {:error, {game.id, :not_found}}

  defp sync_game(game, external) do
    case Repo.transaction(fn -> apply_external(game, external) end) do
      {:ok, updated} -> {:ok, sync_result(updated)}
      {:error, reason} -> {:error, {game.id, reason}}
    end
  end

  defp apply_external(game, external) do
    attrs =
      Map.merge(signals(external), %{
        cover_url: cover_url(external),
        developer: company(external, "developer"),
        publisher: company(external, "publisher"),
        synced_at: DateTime.utc_now()
      })
      |> put_canonical_slug(external)
      |> put_clear_title(game.title, external)

    game =
      case game |> Game.changeset(attrs) |> Repo.update() do
        {:ok, game} -> game
        {:error, changeset} -> Repo.rollback({:game_sync_failed, changeset.errors})
      end

    external_releases(external)
    |> Enum.reduce_while(:ok, fn {platform, date, precision}, :ok ->
      case upsert_release(game, platform, date, precision) do
        {:ok, _release} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> Repo.rollback({:release_sync_failed, reason})
      :ok -> :ok
    end

    drop_unlisted_releases(game, external)
    suggestion = suggested_availability(external)

    %{
      game: Repo.preload(game, :releases, force: true),
      suggested_availability: suggestion,
      availability_difference: suggestion != game.availability
    }
  end

  defp sync_result(%{game: game} = result),
    do: Map.put(result, :game, %{id: game.id, title: game.title})

  defp upsert_release(game, platform, date, precision) do
    attrs = %{
      release_date: date,
      release_date_precision: precision,
      digital_available: true
    }

    case Repo.get_by(Release,
           game_id: game.id,
           platform: platform,
           edition: Release.standard_edition()
         ) do
      nil ->
        %Release{game_id: game.id}
        |> Release.changeset(Map.merge(%{platform: platform, edition: "Edição padrão"}, attrs))
        |> Repo.insert()

      release ->
        release
        |> Release.changeset(attrs)
        |> Repo.update()
    end
  end

  # A platform's standard release that neither the game's IGDB entry nor an entry joined
  # to it lists, as one registered by hand before the sync, is not a version of the game.
  # It goes away unless someone owns, bought, priced or vetoed it, or the eShop sells it.
  defp drop_unlisted_releases(game, external) do
    listed = Enum.map(external_releases(external), &elem(&1, 0))

    unlisted =
      Repo.all(
        from r in Release,
          where:
            r.game_id == ^game.id and r.edition == ^Release.standard_edition() and
              r.platform not in ^listed
      )

    if unlisted != [] do
      joined = joined_platforms(game)

      for release <- unlisted,
          release.platform not in joined,
          blockers(release) == [],
          not Repo.exists?(
            from l in StoreListing,
              where: l.release_id == ^release.id and l.match in [:auto, :confirmed]
          ),
          do: Repo.delete!(release)
    end
  end

  # The platforms of the IGDB entries joined to the game; every platform when IGDB does
  # not answer, so nothing is dropped on a guess.
  defp joined_platforms(game) do
    ids =
      Repo.all(
        from l in GameLink,
          where: l.game_id == ^game.id and l.match in ^GameLink.accepted(),
          select: l.igdb_id
      )

    with [_ | _] <- ids,
         {:ok, %{body: entries}} <- Dockd.IGDB.get_games(ids) do
      entries |> Enum.flat_map(&external_releases/1) |> Enum.map(&elem(&1, 0))
    else
      [] -> []
      _error -> [:switch, :switch_2]
    end
  end

  def suggested_availability(%{"platforms" => platforms}) do
    ids = platforms |> Enum.map(& &1["id"]) |> Enum.uniq()
    nintendo_ids = [Dockd.IGDB.switch_platform_id(), Dockd.IGDB.switch_2_platform_id()]

    cond do
      ids == [Dockd.IGDB.switch_2_platform_id()] ->
        :switch2_exclusive

      ids != [] and Enum.sort(ids) == Enum.sort(nintendo_ids) ->
        :nintendo_exclusive

      ids == [Dockd.IGDB.switch_platform_id()] ->
        :nintendo_exclusive

      Enum.any?(ids, &(&1 in nintendo_ids)) and Enum.any?(ids, &(&1 not in nintendo_ids)) ->
        :multiplatform

      true ->
        nil
    end
  end

  def suggested_availability(_), do: nil

  def release_attributes(external) do
    Enum.map(external_releases(external), fn {platform, date, precision} ->
      %{
        platform: platform,
        edition: "Edição padrão",
        release_date: date,
        release_date_precision: precision,
        digital_available: true
      }
    end)
  end

  defp external_releases(external) do
    platform_ids =
      (external["platforms"] || [])
      |> Enum.map(& &1["id"])
      |> Kernel.++(Enum.map(external["release_dates"] || [], & &1["platform"]))
      |> Enum.filter(
        &(&1 in [Dockd.IGDB.switch_platform_id(), Dockd.IGDB.switch_2_platform_id()])
      )
      |> Enum.uniq()
      |> Enum.sort()

    dates = external["release_dates"] || []

    Enum.map(platform_ids, fn platform_id ->
      release_date =
        dates
        |> Enum.filter(&(&1["platform"] == platform_id))
        |> select_release_date()

      {platform(platform_id), release_date.date, release_date.precision}
    end)
  end

  defp select_release_date([]), do: %{date: nil, precision: :tbd}

  defp select_release_date(dates) do
    dates
    |> Enum.map(fn date ->
      {normalized_date, precision} = normalize_release_date(date)

      %{
        date: normalized_date,
        precision: precision,
        region: date["region"],
        raw_date: date["date"]
      }
    end)
    |> Enum.min_by(fn date ->
      {if(future_date?(date.date), do: 0, else: 1), region_priority(date.region),
       if(is_nil(date.date), do: 1, else: 0), date.date || ~D[9999-12-31],
       date.raw_date || 9_223_372_036_854_775_807}
    end)
  end

  defp normalize_release_date(%{"date" => date} = release) when is_integer(date) do
    precision = release_precision(release)

    case precision do
      :tbd -> {nil, :tbd}
      _ -> {truncate_date(DateTime.from_unix!(date) |> DateTime.to_date(), precision), precision}
    end
  end

  defp normalize_release_date(_), do: {nil, :tbd}

  defp release_precision(%{"category" => category}) when not is_nil(category),
    do: precision_from_format(category)

  defp release_precision(%{"date_format" => format}), do: precision_from_format(format)
  defp release_precision(_), do: :day

  defp precision_from_format(value) when value in [0, "0", "day", "YYYYMMMMDD"], do: :day
  defp precision_from_format(value) when value in [1, "1", "month", "YYYYMMMM"], do: :month
  defp precision_from_format(value) when value in [2, "2", "year", "YYYY"], do: :year

  defp precision_from_format(value) when value in [3, 4, 5, 6, "3", "4", "5", "6", "quarter"],
    do: :quarter

  defp precision_from_format(value) when value in [7, "7", "tbd", "TBD"], do: :tbd
  defp precision_from_format(_), do: :day

  defp truncate_date(date, :day), do: date
  defp truncate_date(%Date{year: year}, :year), do: Date.new!(year, 1, 1)
  defp truncate_date(%Date{year: year, month: month}, :month), do: Date.new!(year, month, 1)

  defp truncate_date(%Date{year: year, month: month}, :quarter) do
    quarter_month = div(month - 1, 3) * 3 + 1
    Date.new!(year, quarter_month, 1)
  end

  defp truncate_date(date, :tbd), do: date

  defp future_date?(%Date{} = date), do: Date.compare(date, Date.utc_today()) == :gt
  defp future_date?(_), do: false

  defp region_priority(8), do: 0
  defp region_priority(10), do: 1
  defp region_priority(1), do: 2
  defp region_priority(_), do: 3

  defp platform(130), do: :switch
  defp platform(508), do: :switch_2

  # What the catalog search compares and orders by.
  defp signals(external),
    do: %{
      alternative_names:
        (external["alternative_names"] || [])
        |> Enum.map(& &1["name"])
        |> Enum.filter(&is_binary/1),
      rating_count: external["total_rating_count"],
      hypes: external["hypes"]
    }

  # The catalog's canonical link to a game always follows IGDB's own slug, kept in sync
  # on every refresh: a slug guessed locally at manual creation or match time (from a
  # shortened title) never resolves to the game's real IGDB page.
  defp put_canonical_slug(attrs, %{"slug" => slug}) when is_binary(slug) and slug != "",
    do: Map.put(attrs, :slug, slug)

  defp put_canonical_slug(attrs, _external), do: attrs

  # A manually typed or matched title is corrected to IGDB's official name only when the
  # difference is unambiguous (the local title shortened or missing the official prefix);
  # anything else stays for the dono to decide, so a same-game rename never guesses wrong.
  defp put_clear_title(attrs, local_title, %{"name" => official})
       when is_binary(official) and is_binary(local_title) do
    if clear_rename?(local_title, official), do: Map.put(attrs, :title, official), else: attrs
  end

  defp put_clear_title(attrs, _local_title, _external), do: attrs

  @doc false
  def clear_rename?(local_title, official_name) do
    local = normalize_title(local_title)
    official = normalize_title(official_name)

    local != official and
      (String.starts_with?(official, local <> " ") or String.ends_with?(official, " " <> local))
  end

  defp cover_url(%{"cover" => %{"image_id" => id}}) when is_binary(id),
    do: "https://images.igdb.com/igdb/image/upload/t_cover_big/#{id}.jpg"

  defp cover_url(_), do: nil

  defp company(%{"involved_companies" => companies}, role),
    do:
      companies
      |> Enum.find_value(fn c ->
        if c[role] && get_in(c, ["company", "name"]), do: get_in(c, ["company", "name"])
      end)

  defp company(_, _), do: nil

  @doc """
  Finds a local game by its IGDB identifier, or by another entry that is the same game
  (an edition, the Switch 2 Edition, a merged duplicate).
  """
  def get_game_by_igdb_id(igdb_id) when is_integer(igdb_id),
    do: igdb_id |> List.wrap() |> local_games() |> Map.get(igdb_id)

  # IGDB id => local game, by the game's own id or an accepted link.
  defp local_games([]), do: %{}

  defp local_games(ids) do
    own = Repo.all(from g in Game, where: g.igdb_id in ^ids, preload: :releases)

    linked =
      Repo.all(
        from g in Game,
          join: l in GameLink,
          on: l.game_id == g.id,
          where: l.igdb_id in ^ids and l.match in ^GameLink.accepted(),
          preload: :releases,
          select: {l.igdb_id, g}
      )

    Map.merge(Map.new(linked), Map.new(own, &{&1.igdb_id, &1}))
  end

  @result_limit 100

  @doc """
  Searches the catalog by title or IGDB alternative name, minding neither case, accents
  nor punctuation, the most rated first. Every result is a game of the catalog, as
  `%{title:, cover_url:, platforms:, first_date:, year:, game:}`.
  """
  def search(query) when is_binary(query) do
    case Game.fold(query) do
      "" ->
        []

      # Folded text holds only letters and digits: nothing LIKE reads as a wildcard.
      folded ->
        Repo.all(
          from game in Game,
            where: like(game.search_text, ^"%#{folded}%"),
            order_by: [desc_nulls_last: game.rating_count, asc: game.title],
            limit: @result_limit,
            preload: :releases
        )
        |> results(Date.utc_today())
    end
  end

  @showcase_limit 50

  @doc """
  A showcase list of the catalog, in the shape of `search/1`:

    * `:upcoming` not out yet, the ones dated to the day first, soonest first;
    * `:recent` out in the last 90 days, most rated and awaited first;
    * `:popular` out in the last year, most rated and awaited first.

  A game is out when one of its releases is (`Release.launch/3`).
  """
  def showcase(list) when list in [:upcoming, :recent, :popular] do
    today = Date.utc_today()

    dated =
      from r in Release, where: r.release_date > ^Date.add(today, -366), select: r.game_id

    Repo.all(from game in Game, where: game.id in subquery(dated), preload: :releases)
    |> results(today)
    |> showcase_list(list, today)
    |> Enum.take(@showcase_limit)
  end

  defp showcase_list(results, :upcoming, _today),
    do:
      results
      |> Enum.filter(&(&1.launch == :upcoming))
      |> Enum.sort_by(&{&1.precision != :day, Date.to_gregorian_days(&1.first_date)})

  defp showcase_list(results, :recent, today), do: released_since(results, today, 90)
  defp showcase_list(results, :popular, today), do: released_since(results, today, 365)

  defp released_since(results, today, days) do
    since = Date.add(today, -days)

    results
    |> Enum.filter(&(&1.launch == :released and Date.compare(&1.first_date, since) == :gt))
    |> Enum.sort_by(&(-((&1.game.rating_count || 0) + (&1.game.hypes || 0))))
  end

  # A game's card: its platforms and when it comes out, from the first release that is
  # out or, when none is, the first one to come.
  defp results(games, today) do
    statuses =
      games |> Enum.flat_map(& &1.releases) |> Enum.map(& &1.id) |> Dockd.Pricing.sales_statuses()

    Enum.map(games, fn game ->
      launches = Enum.map(game.releases, &{&1, Release.launch(&1, today, statuses[&1.id])})
      first = first_release(launches, :released) || first_release(launches, :upcoming)

      %{
        title: game.title,
        cover_url: game.cover_url,
        platforms: game.releases |> Enum.map(& &1.platform) |> Enum.uniq() |> Enum.sort(),
        launch: first && elem(first, 1),
        precision: first && elem(first, 0).release_date_precision,
        first_date: first && elem(first, 0).release_date,
        year: first && elem(first, 0).release_date && elem(first, 0).release_date.year,
        game: game
      }
    end)
  end

  defp first_release(launches, launch) do
    launches
    |> Enum.filter(fn {release, state} -> state == launch and release.release_date end)
    |> Enum.min_by(fn {release, _} -> release.release_date end, Date, fn -> nil end)
  end

  defp fetch_externals([]), do: []

  defp fetch_externals(ids) do
    ids
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn chunk ->
      case Dockd.IGDB.get_games(chunk) do
        {:ok, %{body: externals}} when is_list(externals) -> externals
        _ -> []
      end
    end)
  end

  @doc """
  Imports an IGDB work into the catalog with its Nintendo releases, or returns the
  existing one. An edition or Switch 2 Edition imports (or finds) its parent game
  instead and joins it; a remaster, expanded game or port of a game already in the
  catalog comes in as a game of its own and waits for a person to say whether it is
  the same one (`list_review_links/0`).
  """
  def import_igdb(igdb_id) when is_integer(igdb_id), do: import_igdb(igdb_id, 2)

  defp import_igdb(igdb_id, depth) do
    case get_game_by_igdb_id(igdb_id) do
      %Game{} = game ->
        {:ok, game}

      nil ->
        with true <- Dockd.IGDB.configured?() || {:error, :not_configured},
             {:ok, external} <- fetch_external(igdb_id) do
          import_external(external, depth, true)
        end
    end
  end

  defp fetch_external(igdb_id) do
    case Dockd.IGDB.get_games([igdb_id]) do
      {:ok, %{body: [external]}} -> {:ok, external}
      {:ok, %{body: _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # The depth stops an edition of an edition from walking IGDB for good. Without
  # `children?` the entries that are this game wait for `resolve_families/1`.
  defp import_external(external, depth, children?) do
    with {kind, parent_id} <- IgdbFamily.relation(external),
         true <- depth > 0 and IgdbFamily.automatic?(kind),
         {:ok, parent} <- nintendo_parent(parent_id, depth, children?) do
      apply_family({:link, parent, external["id"], kind, :auto})
      if kind == :switch_2_edition, do: apply_family({:switch_2_release, parent, external})
      {:ok, get_game!(parent.id)}
    else
      _ -> import_own(external, children?)
    end
  end

  # The local game of an IGDB entry sold on a Nintendo platform, imported when missing.
  defp nintendo_parent(igdb_id, depth, children?) do
    case get_game_by_igdb_id(igdb_id) do
      %Game{} = game ->
        {:ok, game}

      nil ->
        with {:ok, external} <- fetch_external(igdb_id),
             true <- IgdbFamily.nintendo?(external) || :not_nintendo,
             do: import_external(external, depth - 1, children?)
    end
  end

  defp import_own(external, children?) do
    with {:ok, game} <- create_imported(import_attrs(external)) do
      Enum.each(release_attributes(external), &create_release(game.id, &1))
      game = get_game!(game.id)

      # A doubtful child of a game already here, then the entries that are this game.
      Enum.each(own_actions([{game, external}], MapSet.new()), &apply_family/1)
      if children?, do: Enum.each(children_actions([game]), &apply_family/1)
      {:ok, get_game!(game.id)}
    end
  end

  # IGDB slugs are unique there, but a game typed in by hand may hold one already.
  defp create_imported(attrs) do
    with {:error, %Ecto.Changeset{errors: errors} = changeset} <- create_game(attrs) do
      if Keyword.has_key?(errors, :slug),
        do:
          create_game(%{
            attrs
            | slug: "#{attrs.slug || Game.slugify(attrs.title)}-#{attrs.igdb_id}"
          }),
        else: {:error, changeset}
    end
  end

  defp import_attrs(external) do
    Map.merge(signals(external), %{
      title: external["name"],
      slug: external["slug"],
      igdb_id: external["id"],
      availability: suggested_availability(external) || :multiplatform,
      cover_url: cover_url(external),
      developer: company(external, "developer"),
      publisher: company(external, "publisher"),
      synced_at: DateTime.utc_now()
    })
  end

  # ---------------------------------------------------------------------------
  # Curation: the catalog is what the criterion admits

  @doc """
  Brings the catalog to the criterion (`Dockd.Catalog.Curation`): imports every IGDB
  entry it admits that is not here yet, an edition or Switch 2 Edition through its
  game, each committed on its own, so a run that stops is picked up by the next one.
  The entries that are the same game are joined afterwards by `resolve_families/1`.

  With `prune: true` it also removes the games with an IGDB id that the criterion
  leaves out and no account refers to (entry, ownership, purchase, price seen or veto);
  never when the eShop ranking was not read, since its games would look unpopular.

  Returns `{:ok, report}` with `admitted`, `imported`, `failed` (`{igdb_id, reason}`),
  `kept` (titles outside the criterion kept for an account), `pruned` (titles),
  `excluded` (reason => `%{count:, sample:}`, most rated first) and `eshop`.
  """
  def curate(opts \\ []) do
    with true <- Dockd.IGDB.configured?() || {:error, :not_configured},
         {:ok, %{decisions: decisions, eshop: eshop}} <- Curation.survey() do
      admitted = for {entry, :admit} <- decisions, do: entry
      {games, failed} = import_admitted(admitted)
      {in_use, unused} = games |> outside_criterion() |> Enum.split_with(&in_use?/1)
      prune? = Keyword.get(opts, :prune, false) and eshop == :ok

      if prune? do
        Enum.each(unused, &Repo.delete!/1)
        remove_orphaned_review_links()
      end

      {:ok,
       %{
         admitted: length(admitted),
         imported: Enum.count(games, &elem(&1, 1)),
         failed: failed,
         kept: Enum.map(in_use, & &1.title),
         pruned: if(prune?, do: Enum.map(unused, & &1.title), else: []),
         excluded: excluded_report(decisions),
         eshop: eshop
       }}
    end
  end

  # `{[{game_id, imported?}], [{igdb_id, reason}]}`: IGDB is asked 500 entries at a time,
  # and an entry already here, by its own id or a link, is not asked at all.
  defp import_admitted(entries) do
    ids = Enum.map(entries, & &1["id"])
    here = local_games(ids)
    found = for {_igdb_id, game} <- here, uniq: true, do: {game.id, false}

    {imported, failed} =
      ids
      |> Enum.reject(&Map.has_key?(here, &1))
      |> Enum.chunk_every(500)
      |> Enum.flat_map(&import_chunk/1)
      |> Enum.split_with(&match?({:ok, _}, &1))

    Logger.info("Catálogo: #{length(imported)} jogos importados, #{length(failed)} falharam")

    {Enum.uniq_by(found ++ Enum.map(imported, &elem(&1, 1)), &elem(&1, 0)),
     Enum.map(failed, &elem(&1, 1))}
  end

  defp import_chunk(ids) do
    case Dockd.IGDB.get_games(ids) do
      {:ok, %{body: externals}} when is_list(externals) ->
        listed = MapSet.new(externals, & &1["id"])

        Enum.map(externals, &import_curated/1) ++
          for id <- ids, id not in listed, do: {:error, {id, :not_found}}

      {:error, reason} ->
        Enum.map(ids, &{:error, {&1, reason}})
    end
  end

  # An earlier entry of the run may have brought this one in, as the game of its edition.
  defp import_curated(external) do
    case get_game_by_igdb_id(external["id"]) do
      %Game{} = game ->
        {:ok, {game.id, false}}

      nil ->
        case import_external(external, 2, false) do
          {:ok, game} -> {:ok, {game.id, true}}
          {:error, reason} -> {:error, {external["id"], reason}}
        end
    end
  end

  defp outside_criterion(games) do
    kept = Enum.map(games, &elem(&1, 0))

    Repo.all(
      from g in Game,
        where: not is_nil(g.igdb_id) and g.id not in ^kept,
        order_by: g.title,
        preload: :releases
    )
  end

  defp in_use?(game) do
    Repo.exists?(from e in Entry, where: e.game_id == ^game.id) or
      Enum.any?(game.releases, &(blockers(&1) != []))
  end

  defp excluded_report(decisions) do
    for({entry, {:exclude, reason}} <- decisions, do: {reason, entry})
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {reason, entries} ->
      sample =
        entries
        |> Enum.sort_by(&(-(&1["total_rating_count"] || 0)))
        |> Enum.take(10)
        |> Enum.map(& &1["name"])

      {reason, %{count: length(entries), sample: sample}}
    end)
  end

  # ---------------------------------------------------------------------------
  # Family: the other IGDB entries that are the same game

  @doc """
  Finds, for every game with an IGDB id, the entries that are the same game, and joins
  them (`Dockd.Catalog.IgdbFamily`): a game imported by its edition's entry moves to
  the parent's id; a duplicate imported as an edition or Switch 2 Edition merges into
  its parent; the Switch 2 Edition becomes the parent's Switch 2 release. A remaster,
  expanded game or port whose parent is also here waits for review.

  With `dry_run: true` nothing changes. Returns the steps, as
  `%{step:, game:, igdb_id:, kind:}`.
  """
  def resolve_families(opts \\ []) do
    if Dockd.IGDB.configured?() do
      games = igdb_games()
      externals = games |> Enum.map(& &1.igdb_id) |> fetch_externals() |> Map.new(&{&1["id"], &1})
      pairs = for game <- games, external = externals[game.igdb_id], do: {game, external}
      own = own_actions(pairs, nintendo_parents(pairs))

      if Keyword.get(opts, :dry_run, false) do
        Enum.map(own ++ children_actions(games), &describe/1)
      else
        Enum.each(own, &apply_family/1)
        children = children_actions(igdb_games())
        Enum.each(children, &apply_family/1)
        Enum.map(own ++ children, &describe/1)
      end
    else
      {:error, :not_configured}
    end
  end

  defp igdb_games,
    do: Repo.all(from g in Game, where: not is_nil(g.igdb_id), preload: :releases)

  # The parents, not in the catalog, that are sold on a Nintendo platform.
  defp nintendo_parents(pairs) do
    ids =
      for {_game, external} <- pairs,
          {kind, parent} <- [IgdbFamily.relation(external)],
          IgdbFamily.automatic?(kind),
          uniq: true,
          do: parent

    local = local_games(ids)

    ids
    |> Enum.reject(&Map.has_key?(local, &1))
    |> fetch_externals()
    |> Enum.filter(&IgdbFamily.nintendo?/1)
    |> MapSet.new(& &1["id"])
  end

  # What a game's own entry says: it is an edition of another game.
  defp own_actions(pairs, nintendo) do
    parents =
      pairs
      |> Enum.flat_map(fn {_game, external} ->
        case IgdbFamily.relation(external) do
          {_kind, parent} -> [parent]
          :own -> []
        end
      end)
      |> local_games()

    linked = linked_ids(Enum.map(pairs, &elem(&1, 0).igdb_id))

    Enum.flat_map(pairs, fn {game, external} ->
      own_action(game, IgdbFamily.relation(external), parents, nintendo, linked)
    end)
  end

  defp own_action(_game, :own, _parents, _nintendo, _linked), do: []

  defp own_action(game, {kind, parent_id}, parents, nintendo, linked) do
    parent = parents[parent_id]
    other? = parent != nil and parent.id != game.id
    automatic? = IgdbFamily.automatic?(kind)

    cond do
      automatic? and other? -> [{:merge, parent, game, kind}]
      automatic? and parent_id in nintendo -> [{:repoint, game, parent_id, kind}]
      other? and game.igdb_id not in linked -> [{:link, parent, game.igdb_id, kind, :review}]
      true -> []
    end
  end

  # What IGDB lists as editions and children of the games.
  defp children_actions(games) do
    parents = Map.new(games, &{&1.igdb_id, &1})
    children = children(Map.keys(parents))
    ids = Enum.map(children, & &1["id"])
    own = Repo.all(from g in Game, where: g.igdb_id in ^ids) |> Map.new(&{&1.igdb_id, &1})
    linked = linked_ids(ids)

    Enum.flat_map(children, fn child ->
      with {kind, parent_id} <- IgdbFamily.relation(child),
           %Game{} = parent <- parents[parent_id] do
        child_actions(parent, child, kind, own[child["id"]], child["id"] in linked)
      else
        _ -> []
      end
    end)
  end

  defp child_actions(parent, child, kind, own, linked?) do
    duplicate? = own != nil and own.id != parent.id

    cond do
      not IgdbFamily.automatic?(kind) ->
        if duplicate? and not linked?, do: [{:link, parent, child["id"], kind, :review}], else: []

      duplicate? ->
        [{:merge, parent, own, kind} | switch_2_actions(parent, child, kind)]

      linked? ->
        switch_2_actions(parent, child, kind)

      true ->
        [{:link, parent, child["id"], kind, :auto} | switch_2_actions(parent, child, kind)]
    end
  end

  defp switch_2_actions(parent, child, :switch_2_edition) do
    if switch_2_changed?(parent, child), do: [{:switch_2_release, parent, child}], else: []
  end

  defp switch_2_actions(_parent, _child, _kind), do: []

  # Whether the parent lacks the Switch 2 release the edition describes, or dates it
  # differently.
  defp switch_2_changed?(%Game{releases: releases}, child) when is_list(releases) do
    current =
      Enum.find(releases, &(&1.platform == :switch_2 and Release.standard?(&1)))

    case Enum.find(external_releases(child), &(elem(&1, 0) == :switch_2)) do
      nil ->
        false

      {_, date, precision} ->
        current == nil or
          {current.release_date, current.release_date_precision} != {date, precision}
    end
  end

  defp switch_2_changed?(_parent, _child), do: true

  defp children([]), do: []

  defp children(ids) do
    ids
    |> Enum.chunk_every(100)
    |> Enum.flat_map(fn chunk ->
      case Dockd.IGDB.children(chunk) do
        {:ok, children} ->
          children

        {:error, reason} ->
          Logger.warning("IGDB: edições e versões não lidas: #{inspect(reason)}")
          []
      end
    end)
  end

  defp linked_ids(ids),
    do: Repo.all(from l in GameLink, where: l.igdb_id in ^ids, select: l.igdb_id) |> MapSet.new()

  defp apply_family({:link, game, igdb_id, kind, match}) do
    %GameLink{}
    |> GameLink.changeset(%{igdb_id: igdb_id, game_id: game.id, kind: kind, match: match})
    |> Repo.insert(on_conflict: :nothing, conflict_target: :igdb_id)
  end

  defp apply_family({:switch_2_release, game, child}) do
    case Enum.find(external_releases(child), &(elem(&1, 0) == :switch_2)) do
      {platform, date, precision} -> upsert_release(game, platform, date, precision)
      nil -> :ok
    end
  end

  defp apply_family({:merge, winner, loser, kind}),
    do: merge_games(winner, loser, kind: kind, match: :auto)

  defp apply_family({:repoint, game, parent_id, kind}) do
    Repo.transaction(fn ->
      game |> Game.changeset(%{igdb_id: parent_id}) |> Repo.update!()
      apply_family({:link, game, game.igdb_id, kind, :auto})
    end)
  end

  defp describe({step, game, igdb_id, kind, match}) when step == :link,
    do: %{step: :link, game: brief(game), igdb_id: igdb_id, kind: kind, match: match}

  defp describe({:switch_2_release, game, child}),
    do: %{
      step: :switch_2_release,
      game: brief(game),
      igdb_id: child["id"],
      kind: :switch_2_edition
    }

  defp describe({:merge, winner, loser, kind}),
    do: %{
      step: :merge,
      game: brief(winner),
      igdb_id: loser.igdb_id,
      kind: kind,
      merged: brief(loser)
    }

  defp describe({:repoint, game, parent_id, kind}),
    do: %{step: :repoint, game: brief(game), igdb_id: parent_id, kind: kind, from: game.igdb_id}

  defp brief(game), do: %{id: game.id, title: game.title}

  @doc """
  Merges `loser` into `winner`, for good: every release, with its ownerships,
  purchases, price observations, vetoes, events and store listing, moves to the winner
  (`Dockd.Catalog.Merge`); the accounts' entries become one; the loser's IGDB id becomes
  a link of the winner (`kind`, default `:merged`; `match`, default `:confirmed`).
  """
  def merge_games(winner, loser, opts \\ [])

  def merge_games(%Game{id: id}, %Game{id: id}, _opts), do: {:error, :same_game}

  def merge_games(%Game{} = winner, %Game{} = loser, opts) do
    with {:ok, game, _undo} <- merge(winner, loser, opts), do: {:ok, game}
  end

  defp merge(winner, loser, opts) do
    link = %{
      kind: Keyword.get(opts, :kind, :merged),
      match: Keyword.get(opts, :match, :confirmed)
    }

    Ecto.Multi.new()
    |> Ecto.Multi.run(:releases, fn repo, _ -> Merge.releases(repo, winner.id, loser.id) end)
    |> Ecto.Multi.run(:entries, fn repo, _ -> Merge.entries(repo, winner.id, loser.id) end)
    |> Ecto.Multi.run(:games, fn repo, _ -> Merge.game(repo, winner.id, loser, link) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{releases: releases, entries: entries, games: games}} ->
        {:ok, get_game!(winner.id), %Merge.Undo{ops: releases ++ entries ++ games}}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Puts two merged games back as they were, from what `confirm_game_link/1` returned:
  the link that asked is in review again. Only while the screen that merged them is
  open, and before anything else touched them.
  """
  def undo_merge(%Merge.Undo{ops: ops}) do
    case Repo.transaction(fn -> Merge.undo(Repo, ops) end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [Ecto.ConstraintError, Postgrex.Error] -> {:error, error}
  end

  @doc "Links waiting for a person: `%{link:, game:, candidate:}`, the candidate being the game that may be `game`."
  def list_review_links do
    Repo.all(
      from l in GameLink,
        join: g in assoc(l, :game),
        join: c in Game,
        on: c.igdb_id == l.igdb_id,
        where: l.match == :review,
        order_by: [asc: g.title],
        preload: [game: {g, :releases}],
        select: {l, c}
    )
    |> Enum.map(fn {link, candidate} ->
      %{link: link, game: link.game, candidate: Repo.preload(candidate, :releases)}
    end)
  end

  @doc "How many resolvable links wait for review."
  def review_link_count do
    Repo.aggregate(
      from(l in GameLink,
        join: c in Game,
        on: c.igdb_id == l.igdb_id,
        where: l.match == :review
      ),
      :count
    )
  end

  @doc "Deletes review links whose candidate game is no longer in the catalog."
  def remove_orphaned_review_links do
    orphaned =
      from(l in GameLink,
        left_join: c in Game,
        on: c.igdb_id == l.igdb_id,
        where: l.match == :review and is_nil(c.id),
        select: l.id
      )

    {count, _} = Repo.delete_all(from(l in GameLink, where: l.id in subquery(orphaned)))
    count
  end

  @doc "A game link."
  def get_game_link!(id), do: Repo.get!(GameLink, id)

  @doc """
  It is the same game: the candidate merges into the linked game. Returns the game and
  what `undo_merge/1` needs to put them apart again.
  """
  def confirm_game_link(%GameLink{match: :review} = link) do
    game = Repo.get!(Game, link.game_id)

    case Repo.get_by(Game, igdb_id: link.igdb_id) do
      nil ->
        with {:ok, _} <- link |> GameLink.changeset(%{match: :confirmed}) |> Repo.update() do
          ops = [{:set, GameLink, [link.id], [match: :review, updated_at: link.updated_at]}]
          {:ok, get_game!(game.id), %Merge.Undo{ops: ops}}
        end

      candidate ->
        merge(game, candidate, kind: link.kind, match: :confirmed)
    end
  end

  def confirm_game_link(%GameLink{}), do: {:error, :not_in_review}

  @doc "It is another game: the link stays rejected and is not asked again."
  def reject_game_link(%GameLink{match: :review} = link),
    do: link |> GameLink.changeset(%{match: :rejected}) |> Repo.update()

  def reject_game_link(%GameLink{}), do: {:error, :not_in_review}

  @doc "Desfazer after It is another game: the link waits for review again."
  def reopen_game_link(%GameLink{match: :rejected} = link),
    do: link |> GameLink.changeset(%{match: :review}) |> Repo.update()

  def reopen_game_link(%GameLink{}), do: {:error, :not_rejected}

  def match_igdb(opts \\ []) do
    if Dockd.IGDB.configured?() do
      dry_run = Keyword.get(opts, :dry_run, false)
      games = Repo.all(from game in Game, where: is_nil(game.igdb_id))
      classified = Enum.map(games, &classify_match/1)
      matches = Enum.filter(classified, &(&1.status == :matched))

      unless dry_run, do: apply_matches(matches)

      %{
        matched: Enum.map(matches, &match_result/1),
        ambiguous:
          classified |> Enum.filter(&(&1.status == :ambiguous)) |> Enum.map(&match_result/1),
        not_found:
          classified |> Enum.filter(&(&1.status == :not_found)) |> Enum.map(&match_result/1)
      }
    else
      {:error, :not_configured}
    end
  end

  defp apply_matches(matches) do
    Enum.each(matches, fn item ->
      attrs =
        %{igdb_id: item.candidate["id"]}
        |> put_canonical_slug(item.candidate)
        |> put_clear_title(item.game.title, item.candidate)

      Repo.update!(Game.changeset(item.game, attrs))
    end)
  end

  defp classify_match(game) do
    candidates = search_candidates(game.title)
    switch = candidates |> Enum.filter(&switch_candidate?/1) |> Enum.uniq_by(& &1["id"])

    exact = Enum.filter(switch, &exact_title?(game.title, &1))
    variants = Enum.filter(switch, &obvious_variant?(game.title, &1))

    {status, candidate} = select_candidate(exact, variants)
    %{game: game, status: if(candidate == [], do: :not_found, else: status), candidate: candidate}
  end

  defp search_candidates(title) do
    case Dockd.IGDB.search(title) do
      {:ok, %{body: body}} -> body
      _ -> []
    end
  end

  defp switch_candidate?(candidate),
    do: Enum.any?(candidate["platforms"] || [], &(&1["id"] in [130, 508]))

  defp exact_title?(title, candidate),
    do: Enum.any?(candidate_titles(candidate), &(normalize_title(&1) == normalize_title(title)))

  defp obvious_variant?(title, candidate) do
    normalized_title = normalize_title(title)

    Enum.any?(candidate_titles(candidate), fn name ->
      normalized_name = normalize_title(name)

      normalized_title != normalized_name and
        String.starts_with?(normalized_name, normalized_title <> " ")
    end)
  end

  defp candidate_titles(candidate) do
    [candidate["name"] | Enum.map(candidate["alternative_names"] || [], & &1["name"])]
    |> Enum.filter(&is_binary/1)
  end

  defp normalize_title(title) do
    title
    |> String.replace("&", " and ")
    |> String.normalize(:nfd)
    |> String.replace(~r/[\p{Mn}]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/\b(?:iii|3)\b/u, "3")
    |> String.replace(~r/\b(?:ii|2)\b/u, "2")
    |> String.replace(~r/\b(?:iv|4)\b/u, "4")
  end

  defp select_candidate([one], _switch), do: {:matched, one}
  defp select_candidate(exact, _switch) when exact != [], do: {:ambiguous, exact}
  defp select_candidate([], [one]), do: {:matched, one}
  defp select_candidate([], switch), do: {:ambiguous, switch}

  defp match_result(%{game: game, candidate: candidate}),
    do: %{game_id: game.id, title: game.title, candidate: candidate}
end
