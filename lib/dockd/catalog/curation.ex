defmodule Dockd.Catalog.Curation do
  @moduledoc """
  Which IGDB entries make the catalog, by the criterion in `config :dockd,
  :catalog_criteria` (documented in the README):

    * a Switch or Switch 2 entry of one of the `game_types`, not an edition of another
      entry (editions and Switch 2 Editions join their game, `Dockd.Catalog.IgdbFamily`);
    * released or still coming: never cancelled, rumored or offline;
    * with a cover;
    * not from a publisher in `excluded_publishers`, by IGDB or by the eShop;
    * popular by any of: the rating count of the entry, or of the game it remasters,
      expands or ports, at least `min_rating_count`; the critics' count at least
      `min_critic_count`; not yet out on Switch and hyped at least `min_hypes`; the
      eShop Brasil popularity rank at most `max_eshop_rank`; published by Nintendo, by
      IGDB or by the eShop (`Nintendo`, `Nintendo of America`, `Nintendo of Europe` and
      other spellings of the same company);
    * a collection (game_type 3) holds games: one holding only add-ons is a pass or a
      DLC pack, and one holding a single game sold on Switch is an edition of it.

  DLC, expansions, packs, updates, seasons, episodes, mods and forks are other game
  types and never enter. `survey/1` decides every entry and says why it left each one
  out; `Dockd.Catalog.curate/1` imports what it admits. A game already in a library
  stays regardless of the criterion (`Dockd.Catalog.curate/1`'s pruning, not this
  module, spares it).
  """
  require Logger
  alias Dockd.Catalog.{IgdbFamily, Release}
  alias Dockd.{Eshop, IGDB}
  alias Dockd.Pricing.EshopMatch

  # IGDB game_status: offline, cancelled, rumored.
  @gone_statuses [5, 6, 7]
  @game_type_names %{
    1 => "DLC",
    2 => "expansão",
    5 => "mod",
    6 => "episódio",
    7 => "temporada",
    12 => "fork",
    13 => "pacote de conteúdo",
    14 => "atualização"
  }
  @platform_codes %{"NINTENDO_SWITCH" => 130, "NINTENDO_SWITCH_2" => 508}

  @doc "The criterion, from `config :dockd, :catalog_criteria`."
  def criteria, do: :dockd |> Application.fetch_env!(:catalog_criteria) |> Map.new()

  @doc "The IGDB game types left out, with their name in the report."
  def excluded_game_types(criteria \\ criteria()),
    do: Map.drop(@game_type_names, criteria.game_types)

  @doc """
  Reads IGDB and the eShop Brasil ranking and decides every entry. Returns
  `{:ok, %{decisions: [{entry, :admit | {:exclude, reason}}], eshop: :ok | reason}}`;
  the reasons are `:status`, `:no_cover`, `:publisher`, `:unpopular`,
  `:bundle_without_game` and `:edition_of_other`. Without the ranking the survey still
  runs and says why in `eshop`.
  """
  def survey(criteria \\ criteria()) do
    with {:ok, entries} <- IGDB.catalog_entries(criteria.game_types),
         {:ok, parent_counts} <- parent_counts(entries, criteria) do
      {eshop, ranks} = eshop_ranks(entries, criteria)
      context = context(criteria, parent_counts, ranks)

      first = Enum.map(entries, &{&1, decide(&1, context, criteria)})

      with {:ok, contents} <- bundle_contents(first),
           do: {:ok, %{decisions: Enum.map(first, &open_bundle(&1, contents)), eshop: eshop}}
    end
  end

  defp open_bundle({%{"game_type" => 3} = entry, :admit}, contents),
    do: {entry, bundle_decision(entry, contents)}

  defp open_bundle(decided, _contents), do: decided

  @doc """
  What `decide/3` knows besides the entry: `parent_counts` (IGDB id => rating count)
  and `ranks` (IGDB id => `{eshop_rank, eshop_publisher}`).
  """
  def context(criteria, parent_counts \\ %{}, ranks \\ %{}),
    do: %{
      parent_counts: parent_counts,
      ranks: ranks,
      excluded: MapSet.new(criteria.excluded_publishers, &company_key/1)
    }

  @doc "Decides one entry from its `context/3`, but a collection's content."
  def decide(entry, context, criteria) do
    cond do
      entry["game_status"] in @gone_statuses -> {:exclude, :status}
      not is_map(entry["cover"]) -> {:exclude, :no_cover}
      excluded_publisher?(entry, context) -> {:exclude, :publisher}
      not popular?(entry, context, criteria) -> {:exclude, :unpopular}
      true -> :admit
    end
  end

  @doc "The popularity signals of an entry, as the criterion compares them."
  def signals(entry, context) do
    parent = Map.get(context.parent_counts, entry["parent_game"])

    %{
      rating_count: max(entry["total_rating_count"] || 0, parent || 0),
      critic_count: entry["aggregated_rating_count"] || 0,
      hypes: entry["hypes"] || 0,
      eshop_rank: context.ranks |> Map.get(entry["id"], {nil, nil}) |> elem(0)
    }
  end

  @doc "Every reason `popular?/3` would admit this entry by, for the simulation report."
  def popularity_reasons(entry, context, criteria) do
    signals = signals(entry, context)

    [
      rating: signals.rating_count >= criteria.min_rating_count,
      critic: signals.critic_count >= criteria.min_critic_count,
      hype: not released?(entry) and signals.hypes >= criteria.min_hypes,
      eshop_rank: signals.eshop_rank != nil and signals.eshop_rank <= criteria.max_eshop_rank,
      nintendo: nintendo_published?(entry, context)
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp popular?(entry, context, criteria), do: popularity_reasons(entry, context, criteria) != []

  # Not yet out on Switch: unpublished games have no rating history to judge by yet, so
  # the criterion reads their hype instead. Ignores a release elsewhere (PC, other
  # consoles) the way it reads the rating count, entry-scoped, not company-scoped.
  defp released?(entry) do
    platform_ids = entry["platforms"] |> List.wrap() |> Enum.map(& &1["id"])

    entry["release_dates"]
    |> List.wrap()
    |> Enum.filter(&(&1["platform"] in platform_ids))
    |> Release.igdb_launched?()
  end

  defp excluded_publisher?(entry, context), do: publisher?(entry, context, context.excluded)

  defp nintendo_published?(entry, context),
    do: publisher?(entry, context, &(&1 |> company_key() |> String.starts_with?("nintendo")))

  defp publisher?(entry, context, %MapSet{} = keys),
    do: publisher?(entry, context, &MapSet.member?(keys, company_key(&1)))

  defp publisher?(entry, context, matches?) do
    {_rank, store_publisher} = Map.get(context.ranks, entry["id"], {nil, nil})

    (entry["involved_companies"] || [])
    |> Enum.filter(& &1["publisher"])
    |> Enum.map(&get_in(&1, ["company", "name"]))
    |> Kernel.++([store_publisher])
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(matches?)
  end

  # "REDDEER.GAMES" at the eShop is "RedDeer.Games" at IGDB.
  defp company_key(name), do: name |> String.downcase() |> String.replace(~r/[^a-z0-9]/u, "")

  # The rating count of the games that popular-looking remasters, expansions and ports
  # come from, asked only for the entries that are not popular on their own.
  defp parent_counts(entries, criteria) do
    known = Map.new(entries, &{&1["id"], &1["total_rating_count"]})
    lonely = context(criteria)

    wanted =
      for entry <- entries,
          is_integer(entry["parent_game"]),
          not popular?(entry, lonely, criteria),
          uniq: true,
          do: entry["parent_game"]

    {inside, outside} = Enum.split_with(wanted, &Map.has_key?(known, &1))
    counts = Map.new(inside, &{&1, known[&1]})

    case outside do
      [] ->
        {:ok, counts}

      ids ->
        with {:ok, parents} <- IGDB.rating_counts(ids),
             do: {:ok, Map.merge(counts, Map.new(parents, &{&1["id"], &1["total_rating_count"]}))}
    end
  end

  # The eShop Brasil ranking by IGDB entry: a store game matched by its title (or the
  # title without the edition) to an entry of the same platform, the most rated when
  # several share it.
  defp eshop_ranks(entries, criteria) do
    case Eshop.popular(criteria.max_eshop_rank) do
      {:ok, hits} ->
        {:ok, match_ranks(entries, hits)}

      {:error, reason} ->
        Logger.warning("Catálogo: ranking da eShop não lido: #{inspect(reason)}")
        {reason, %{}}
    end
  end

  @doc false
  def match_ranks(entries, hits) do
    index =
      for entry <- entries,
          name <- [entry["name"] | Enum.map(entry["alternative_names"] || [], & &1["name"])],
          is_binary(name),
          key <- title_keys(name),
          platform <- Enum.map(entry["platforms"] || [], & &1["id"]),
          reduce: %{} do
        index -> Map.update(index, {key, platform}, [entry], &[entry | &1])
      end

    hits
    |> Enum.filter(&(EshopMatch.game?(&1) and is_integer(&1["popularityRank"])))
    |> Enum.reduce(%{}, fn hit, ranks ->
      platform = @platform_codes[hit["platformCode"]]
      found = (hit["title"] || "") |> title_keys() |> Enum.find_value(&index[{&1, platform}])
      if found, do: best_rank(ranks, found, hit), else: ranks
    end)
  end

  # The store product ranks the most rated entry of its title, by its best rank.
  defp best_rank(ranks, found, hit) do
    entry = Enum.max_by(found, &(&1["total_rating_count"] || 0))
    ranked = {hit["popularityRank"], hit["softwarePublisher"]}
    Map.update(ranks, entry["id"], ranked, &min(&1, ranked))
  end

  defp title_keys(title) do
    key = EshopMatch.normalize(title)
    Enum.uniq([key, EshopMatch.edition_base(key)])
  end

  # What each admitted collection holds, and what the collections inside it hold.
  defp bundle_contents(decisions) do
    ids = for {%{"game_type" => 3} = entry, :admit} <- decisions, do: entry["id"]

    with {:ok, contents} <- contents_of(ids) do
      inner = for {_bundle, held} <- contents, %{"game_type" => 3} = b <- held, do: b["id"]

      with {:ok, inner} <- contents_of(Enum.uniq(inner) -- ids),
           do: {:ok, Map.merge(inner, contents)}
    end
  end

  defp contents_of([]), do: {:ok, %{}}

  defp contents_of(ids) do
    with {:ok, contents} <- IGDB.bundle_contents(ids) do
      {:ok,
       for content <- contents,
           bundle <- content["bundles"] || [],
           bundle in ids,
           reduce: %{} do
         by_bundle -> Map.update(by_bundle, bundle, [content], &[content | &1])
       end}
    end
  end

  # A collection holds games; a single game sold on Switch makes it that game's edition.
  defp bundle_decision(entry, contents) do
    case Enum.filter(Map.get(contents, entry["id"], []), &game?(&1, contents)) do
      [] -> {:exclude, :bundle_without_game}
      [game] -> if IgdbFamily.nintendo?(game), do: {:exclude, :edition_of_other}, else: :admit
      _collection -> :admit
    end
  end

  # A collection inside a collection is a game when it holds one; a season or
  # expansion pass holds only add-ons.
  defp game?(%{"version_parent" => parent}, _contents) when is_integer(parent), do: false
  defp game?(%{"game_type" => type}, _contents) when type in [0, 4, 8, 9, 10, 11], do: true

  defp game?(%{"game_type" => 3} = bundle, contents),
    do: Enum.any?(Map.get(contents, bundle["id"], []), &game?(&1, %{}))

  defp game?(_content, _contents), do: false
end
