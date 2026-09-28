defmodule Dockd.Pricing do
  @moduledoc """
  Store prices as catalog data: which eShop Brasil product sells each release, the
  price history kept from the daily sync, and the store price a release goes for now.

  The history stores changes, not daily snapshots: a new `StorePrice` only when the
  price, the discount or the sales status changes, otherwise `last_seen_at` moves.
  """
  import Ecto.Query
  require Logger
  alias Dockd.Catalog.{Game, Release}
  alias Dockd.Eshop
  alias Dockd.Library.Entry
  alias Dockd.Pricing.{CurrentPrice, EshopMatch, StoreListing, StorePrice}
  alias Dockd.Repo

  @priced [:auto, :confirmed]
  @locales [:pt_br, :en_us]

  # ---------------------------------------------------------------------------
  # Store price

  @doc """
  The eShop price a release goes for now, or nil when the store does not sell it
  (no accepted listing, not sold in Brazil, withdrawn, not priced yet). The discount
  counts only inside its window. Screens read it through `Dockd.Purchasing.current_price/3`.
  """
  def store_price(release_id, now \\ DateTime.utc_now()) do
    Repo.one(
      from l in StoreListing,
        join: p in subquery(latest_prices()),
        on: p.listing_id == l.id,
        where:
          l.release_id == ^release_id and l.match in ^@priced and not is_nil(p.regular_cents),
        select: p
    )
    |> case do
      nil -> nil
      price -> %{store_current_price(price, now) | release_id: release_id}
    end
  end

  @doc """
  Whether the eShop stopped selling a release it sold (`sales_termination`), as with a
  game now sold only in a bundle. The screen says `fora de venda` instead of no price.
  """
  def withdrawn?(release_id) do
    Repo.exists?(
      from l in StoreListing,
        join: p in subquery(latest_prices()),
        on: p.listing_id == l.id,
        where:
          l.release_id == ^release_id and l.match in ^@priced and
            p.sales_status == "sales_termination"
    )
  end

  @doc """
  The eShop sales status of each release the store sells, by release id, for
  `Dockd.Catalog.Release.launch/3`. A release the store does not sell is absent.
  """
  def sales_statuses([]), do: %{}

  def sales_statuses(release_ids) do
    Repo.all(
      from l in StoreListing,
        where:
          l.release_id in ^release_ids and l.match in ^@priced and not is_nil(l.sales_status),
        select: {l.release_id, l.sales_status}
    )
    |> Map.new()
  end

  defp latest_prices,
    do:
      from(p in StorePrice,
        distinct: p.listing_id,
        order_by: [asc: p.listing_id, desc: p.first_seen_at]
      )

  defp store_current_price(%StorePrice{} = price, now) do
    discounted? =
      price.discount_cents != nil and before?(price.discount_starts_at, now) and
        before?(now, price.discount_ends_at)

    %CurrentPrice{
      price_cents: if(discounted?, do: price.discount_cents, else: price.regular_cents),
      regular_cents: price.regular_cents,
      discount_ends_at: if(discounted?, do: price.discount_ends_at),
      currency: price.currency,
      observed_at: price.last_seen_at,
      sales_status: price.sales_status
    }
  end

  defp before?(nil, _), do: true
  defp before?(_, nil), do: true
  defp before?(left, right), do: DateTime.compare(left, right) != :gt

  # ---------------------------------------------------------------------------
  # Daily sync

  @doc """
  Matches releases without a listing, then refreshes eShop prices. A Nintendo failure,
  or no price at all for listings that should have one, is logged as an error and
  returned, never raised: the IGDB sync that runs before it must not depend on it.
  """
  def sync_eshop(now \\ DateTime.utc_now()) do
    match = run_step("casamento", fn -> match_eshop() end)
    families = run_step("edições", fn -> match_families(now) end)
    prices = run_step("preços", fn -> sync_eshop_prices(now) end)

    case prices do
      {:ok, %{listings: listings, priced: 0}} when listings > 0 ->
        Logger.error("eShop: nenhum preço para #{listings} produtos; a API pode ter mudado")

      _ ->
        :ok
    end

    %{match: match, families: families, prices: prices}
  end

  defp run_step(name, fun) do
    case fun.() do
      {:error, :not_configured} = error ->
        Logger.warning("eShop: #{name} sem chave de busca (ESHOP_ALGOLIA_SEARCH_KEY)")
        error

      {:error, reason} = error ->
        Logger.error("eShop: #{name} falhou: #{inspect(reason)}")
        error

      result ->
        result
    end
  rescue
    exception ->
      Logger.error(
        "eShop: #{name} falhou: " <> Exception.format(:error, exception, __STACKTRACE__)
      )

      {:error, exception}
  end

  @doc """
  Finds the eShop product of every release without a listing, or still in review.
  Searches the game's title and its IGDB alternative names, in the Brazilian index
  first and the American one after (the Brazilian index misses games sold here).
  Exact and edition matches become `:auto` listings; anything weaker waits for review
  with up to three candidates, but only for a game some account follows: the rest of
  the catalog takes safe matches only. A release without a listing is searched again
  on the next run, since the store lists games before launch; weekly when nobody
  follows its game. The games followed go first, then the most rated.
  """
  def match_eshop(now \\ DateTime.utc_now()) do
    if Eshop.configured?() do
      followed = followed_games()

      now
      |> pending_releases(followed)
      |> Enum.group_by(&elem(&1, 0).game)
      |> Enum.sort_by(fn {game, _} ->
        {not MapSet.member?(followed, game.id), -(game.rating_count || 0), game.title}
      end)
      |> match_games(followed, now)
    else
      {:error, :not_configured}
    end
  end

  @research_after_days 7

  # A search failure (a rotated key answers 403) stops the matching, not the prices.
  defp match_games(releases_by_game, followed, now) do
    Enum.reduce_while(releases_by_game, {:ok, %{auto: 0, review: 0, none: 0}}, fn
      {game, releases}, {:ok, counts} ->
        titles = EshopMatch.search_titles(game.title, game.alternative_names || [])
        review? = MapSet.member?(followed, game.id)

        case match_game(titles, releases, review?) do
          {:ok, decisions} ->
            searched(releases, now)
            {:cont, {:ok, count(counts, decisions)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
    end)
  end

  defp followed_games,
    do: Repo.all(from(e in Entry, distinct: true, select: e.game_id)) |> MapSet.new()

  # Each release with its listing in review, or nil.
  defp pending_releases(now, followed) do
    stale = DateTime.add(now, -@research_after_days, :day)
    followed = MapSet.to_list(followed)

    Repo.all(
      from r in Release,
        join: g in Game,
        on: g.id == r.game_id,
        left_join: l in StoreListing,
        on: l.release_id == r.id and l.store == :eshop_br,
        where:
          r.edition == ^Release.standard_edition() and
            (l.match == :review or
               (is_nil(l.id) and
                  (is_nil(r.eshop_searched_at) or r.eshop_searched_at < ^stale or
                     g.id in ^followed))),
        order_by: [asc: r.platform],
        preload: [game: g],
        select: {r, l}
    )
  end

  defp searched(releases, now) do
    ids = Enum.map(releases, &elem(&1, 0).id)
    Repo.update_all(from(r in Release, where: r.id in ^ids), set: [eshop_searched_at: now])
  end

  defp match_game(titles, pending, review?) do
    platforms = pending |> Enum.map(&elem(&1, 0).platform) |> Enum.uniq()
    queries = for locale <- @locales, title <- titles, do: {locale, title}

    with {:ok, hits} <- search_until_settled(queries, titles, platforms, []) do
      decisions =
        Enum.map(pending, fn {release, listing} ->
          decision = EshopMatch.decide(EshopMatch.candidates(titles, hits, release.platform))
          {release, listing, unless_unfollowed(decision, review?)}
        end)

      prices = candidate_prices(decisions)

      {:ok,
       Enum.map(decisions, fn {release, listing, decision} ->
         save_decision(release, listing, decision, prices)
       end)}
    end
  end

  defp unless_unfollowed({:review, _candidates}, false), do: :none
  defp unless_unfollowed(decision, _review?), do: decision

  # The person choosing sees what each candidate costs in Brazil, and whether it is sold.
  defp candidate_prices(decisions) do
    ids =
      for {_release, _listing, {:review, candidates}} <- decisions,
          %{hit: hit} <- candidates,
          uniq: true,
          do: hit["nsuid"]

    with [_ | _] <- ids,
         {:ok, prices} <- Eshop.prices(Enum.take(ids, Eshop.price_batch())) do
      Map.new(prices, &{to_string(&1["title_id"]), price_attrs(&1)})
    else
      [] ->
        %{}

      {:error, reason} ->
        Logger.warning("eShop: preço dos candidatos falhou: #{inspect(reason)}")
        %{}
    end
  end

  # Stops searching as soon as every platform has a match safe to accept.
  defp search_until_settled([], _titles, _platforms, hits), do: {:ok, hits}

  defp search_until_settled([{locale, query} | rest], titles, platforms, hits) do
    with {:ok, found} <- Eshop.search(locale, query) do
      hits = hits ++ found

      settled? =
        Enum.all?(platforms, fn platform ->
          match?({:auto, _}, EshopMatch.decide(EshopMatch.candidates(titles, hits, platform)))
        end)

      if settled?, do: {:ok, hits}, else: search_until_settled(rest, titles, platforms, hits)
    end
  end

  defp save_decision(release, listing, decision, prices) do
    attrs =
      case decision do
        :none ->
          nil

        {:auto, %{hit: hit}} ->
          %{match: :auto, external_id: hit["nsuid"], title: hit["title"], candidates: []}

        {:review, candidates} ->
          %{
            match: :review,
            external_id: nil,
            title: nil,
            candidates: Enum.map(candidates, &candidate(&1, prices))
          }
      end

    save_listing(release, listing, attrs)
  end

  defp save_listing(_release, nil, nil), do: :none

  defp save_listing(_release, listing, nil) do
    Repo.delete!(listing)
    :none
  end

  defp save_listing(release, listing, attrs) do
    changeset =
      StoreListing.changeset(
        listing || %StoreListing{release_id: release.id},
        Map.put(attrs, :store, :eshop_br)
      )

    case Repo.insert_or_update(changeset) do
      {:ok, listing} ->
        listing.match

      # Another release already holds this product: someone has to say which one.
      {:error, %{errors: [external_id: _]}} ->
        save_listing(release, listing, %{
          match: :review,
          external_id: nil,
          title: nil,
          candidates: [
            %{"external_id" => attrs.external_id, "title" => attrs.title, "class" => "exact"}
          ]
        })

      {:error, changeset} ->
        Logger.warning("eShop: versão #{release.id} sem listagem: #{inspect(changeset.errors)}")
        :none
    end
  end

  @platforms %{"NINTENDO_SWITCH" => "switch", "NINTENDO_SWITCH_2" => "switch_2"}

  # Stored as JSON: the price as the API gave it when the candidate was found, so the
  # review shows it and confirming records it without asking Nintendo again.
  defp candidate(%{hit: hit, class: class}, prices) do
    price =
      case Map.fetch(prices, hit["nsuid"]) do
        {:ok, attrs} -> Map.new(attrs, fn {key, value} -> {Atom.to_string(key), value} end)
        :error -> %{}
      end

    Map.merge(price, %{
      "external_id" => hit["nsuid"],
      "title" => hit["title"],
      "class" => Atom.to_string(class),
      "platform" => @platforms[hit["platformCode"]],
      "bundle" => get_in(hit, ["eshopDetails", "productType"]) == "BUNDLE",
      "url" => hit["url"],
      "seen_at" => if(price != %{}, do: DateTime.utc_now())
    })
  end

  defp count(counts, decisions),
    do: Enum.reduce(decisions, counts, &Map.update!(&2, &1, fn n -> n + 1 end))

  # ---------------------------------------------------------------------------
  # Family: the store's editions and Switch 2 Edition of a matched game

  @doc """
  Reads, once, the product page of every base product matched to a standard release,
  and from the family Nintendo gives it (`Dockd.Eshop.product/1`):

    * a bundle holding exactly this game (and content) becomes an edition of it, a
      release of the same platform named as the store sells it, listed and priced at
      once; only a bundle on sale does;
    * the same game on the other platform (the Switch 2 Edition) becomes the listing
      of that platform's release, created when the game lacks it.

  A bundle of several games is a collection, and DLC packs and upgrade packs are not
  games: none of them becomes a release. A page that cannot be read leaves the release
  as it was, to try again on the next run. Returns `{:ok, %{read:, editions:, releases:}}`.
  """
  def match_families(now \\ DateTime.utc_now()) do
    listings =
      Repo.all(
        from l in StoreListing,
          join: r in assoc(l, :release),
          where:
            l.store == :eshop_br and l.match in ^@priced and is_nil(l.family_read_at) and
              like(l.external_id, "7001%") and r.edition == ^Release.standard_edition(),
          order_by: [asc: l.inserted_at],
          preload: [release: r]
      )

    {:ok, Enum.reduce(listings, %{read: 0, editions: 0, releases: 0}, &read_family(&1, &2, now))}
  end

  # Nintendo is asked first, the catalog written after: no transaction waits on the network.
  defp read_family(listing, counts, now) do
    case Eshop.product(listing.external_id) do
      {:ok, product} ->
        others = Enum.reject(product.variations, &(&1.nsuid == product.nsuid))
        taken = taken_ids(Enum.map(others, & &1.nsuid))

        editions =
          others
          |> Enum.filter(
            &(String.starts_with?(&1.nsuid, "7007") and &1.nsuid not in taken and
                edition_of?(&1, product.nsuid))
          )
          |> sold()

        platforms =
          Enum.filter(others, fn other ->
            String.starts_with?(other.nsuid, "7001") and other.nsuid not in taken and
              other.platform not in [nil, product.platform]
          end)

        found =
          Repo.transaction(fn -> join_family(listing, product, editions, platforms, now) end)

        add_counts(counts, found)

      {:error, reason} ->
        Logger.warning("eShop: família de #{listing.external_id} não lida: #{inspect(reason)}")
        counts
    end
  end

  defp add_counts(counts, {:ok, %{editions: editions, releases: releases}}),
    do: %{
      counts
      | read: counts.read + 1,
        editions: counts.editions + editions,
        releases: counts.releases + releases
    }

  defp add_counts(counts, _failed), do: counts

  defp join_family(listing, product, editions, platforms, now) do
    game = Repo.preload(listing.release, [game: :releases], force: true).game

    added =
      Enum.count(editions, fn {bundle, price} ->
        add_edition(game, product.title, bundle, price, now)
      end)

    listed = Enum.count(platforms, &list_other_platform(game, &1))
    listing |> Ecto.Changeset.change(family_read_at: now) |> Repo.update!()
    %{editions: added, releases: listed}
  end

  defp taken_ids(ids),
    do:
      Repo.all(
        from l in StoreListing,
          where: l.store == :eshop_br and l.external_id in ^ids,
          select: l.external_id
      )

  # A bundle whose only game is the base product: the base with content.
  defp edition_of?(bundle, base_nsuid) do
    case Eshop.product(bundle.nsuid) do
      {:ok, %{bundle?: true, contents: contents}} ->
        Enum.filter(contents, &String.starts_with?(&1.nsuid, "7001")) |> Enum.map(& &1.nsuid) ==
          [base_nsuid]

      {:ok, _other} ->
        false

      {:error, reason} ->
        Logger.warning("eShop: pacote #{bundle.nsuid} não lido: #{inspect(reason)}")
        false
    end
  end

  # The bundles the store sells now, each with its price.
  defp sold([]), do: []

  defp sold(bundles) do
    case Eshop.prices(Enum.map(bundles, & &1.nsuid)) do
      {:ok, prices} ->
        by_id = Map.new(prices, &{to_string(&1["title_id"]), price_attrs(&1)})

        for bundle <- bundles,
            %{regular_cents: cents} = price when is_integer(cents) <- [by_id[bundle.nsuid]],
            do: {bundle, price}

      {:error, reason} ->
        Logger.warning("eShop: preço das edições falhou: #{inspect(reason)}")
        []
    end
  end

  defp add_edition(game, store_title, bundle, price, now) do
    base = Enum.find(game.releases, &(&1.platform == bundle.platform and Release.standard?(&1)))
    name = EshopMatch.edition_name(bundle.title, [game.title, store_title])

    name =
      if Enum.any?(game.releases, &(&1.platform == bundle.platform and &1.edition == name)),
        do: String.replace(bundle.title, ["™", "®", "©"], ""),
        else: name

    with %Release{} <- base,
         {:ok, release} <-
           %Release{game_id: game.id}
           |> Release.changeset(%{
             platform: bundle.platform,
             edition: name,
             release_date: base.release_date,
             release_date_precision: base.release_date_precision,
             digital_available: true
           })
           |> Repo.insert(),
         {:ok, listing} <-
           %StoreListing{release_id: release.id}
           |> StoreListing.changeset(%{
             store: :eshop_br,
             match: :auto,
             external_id: bundle.nsuid,
             title: bundle.title,
             family_read_at: now
           })
           |> Repo.insert() do
      record_price(listing, price, now)
      true
    else
      _ -> false
    end
  end

  # The Switch 2 Edition, or the Switch version, of the same game.
  defp list_other_platform(game, product) do
    release =
      Enum.find(game.releases, &(&1.platform == product.platform and Release.standard?(&1))) ||
        Repo.insert!(
          Release.changeset(%Release{game_id: game.id}, %{
            platform: product.platform,
            digital_available: true
          })
        )

    listing = Repo.get_by(StoreListing, release_id: release.id, store: :eshop_br)

    (is_nil(listing) or listing.match == :review) and
      save_listing(release, listing, %{
        match: :auto,
        external_id: product.nsuid,
        title: product.title,
        candidates: []
      }) == :auto
  end

  # ---------------------------------------------------------------------------
  # Review: a person picks the store product the sync could not settle. The listing is
  # catalog data, so any account decides for all of them.

  @doc "Listings waiting for a person to pick the store product, by game and platform."
  def list_review_listings do
    Repo.all(
      from l in StoreListing,
        join: r in assoc(l, :release),
        join: g in assoc(r, :game),
        where: l.store == :eshop_br and l.match == :review,
        order_by: [asc: g.title, asc: r.platform],
        preload: [release: {r, game: g}]
    )
  end

  @doc "How many listings wait for review."
  def review_count,
    do:
      Repo.aggregate(
        from(l in StoreListing, where: l.store == :eshop_br and l.match == :review),
        :count
      )

  @doc "A listing with its release and game."
  def get_listing!(id), do: StoreListing |> Repo.get!(id) |> Repo.preload(release: :game)

  @doc """
  Confirms one of a listing's candidates as the store product and records the price
  seen with it, so the release is priced at once; the daily sync refreshes it.
  """
  def confirm_listing(%StoreListing{match: :review} = listing, external_id) do
    case Enum.find(listing.candidates, &(&1["external_id"] == external_id)) do
      nil ->
        {:error, :not_a_candidate}

      candidate ->
        Repo.transaction(fn -> confirm_candidate(listing, candidate) end)
    end
  end

  def confirm_listing(%StoreListing{}, _external_id), do: {:error, :not_in_review}

  defp confirm_candidate(listing, candidate) do
    changeset =
      StoreListing.changeset(listing, %{
        match: :confirmed,
        external_id: candidate["external_id"],
        title: candidate["title"],
        sales_status: candidate["sales_status"],
        checked_at: candidate["seen_at"]
      })

    case Repo.update(changeset) do
      {:ok, listing} ->
        record_candidate_price(listing, candidate)
        listing

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp record_candidate_price(listing, %{"sales_status" => status, "seen_at" => seen_at} = c)
       when is_binary(status) do
    {:ok, seen_at, _} = DateTime.from_iso8601(to_string(seen_at))

    %StorePrice{listing_id: listing.id}
    |> StorePrice.changeset(%{
      sales_status: status,
      regular_cents: c["regular_cents"],
      discount_cents: c["discount_cents"],
      discount_starts_at: c["discount_starts_at"],
      discount_ends_at: c["discount_ends_at"],
      currency: c["currency"] || "BRL",
      first_seen_at: seen_at,
      last_seen_at: seen_at
    })
    |> Repo.insert!()
  end

  defp record_candidate_price(_listing, _candidate), do: :ok

  @doc "Records that the eShop does not sell the release: it leaves the queue for good."
  def reject_listing(%StoreListing{match: :review} = listing),
    do: listing |> StoreListing.changeset(%{match: :rejected}) |> Repo.update()

  def reject_listing(%StoreListing{}), do: {:error, :not_in_review}

  @doc "Undoes a confirmation or a rejection: the listing waits for review again."
  def reopen_listing(%StoreListing{match: match} = listing)
      when match in [:confirmed, :rejected] do
    Repo.transaction(fn ->
      Repo.delete_all(from p in StorePrice, where: p.listing_id == ^listing.id)

      listing
      |> StoreListing.changeset(%{
        match: :review,
        external_id: nil,
        title: nil,
        sales_status: nil
      })
      |> Repo.update!()
    end)
  end

  def reopen_listing(%StoreListing{}), do: {:error, :not_decided}

  @doc "What a candidate costs, as seen when it was found, or nil when it had no price."
  def candidate_price(candidate, now \\ DateTime.utc_now())

  def candidate_price(%{"regular_cents" => cents, "seen_at" => seen_at} = candidate, now)
      when is_integer(cents) do
    {:ok, seen_at, _} = DateTime.from_iso8601(to_string(seen_at))

    store_current_price(
      %StorePrice{
        regular_cents: cents,
        discount_cents: candidate["discount_cents"],
        discount_starts_at: iso_datetime(candidate["discount_starts_at"]),
        discount_ends_at: iso_datetime(candidate["discount_ends_at"]),
        currency: candidate["currency"] || "BRL",
        sales_status: candidate["sales_status"],
        last_seen_at: seen_at
      },
      now
    )
  end

  def candidate_price(_candidate, _now), do: nil

  defp iso_datetime(nil), do: nil
  defp iso_datetime(%DateTime{} = datetime), do: datetime
  defp iso_datetime(value), do: datetime(value)

  @doc """
  Asks the eShop Brasil price of every accepted listing, #{Eshop.price_batch()} at a
  time, and records what changed. Returns `{:ok, %{listings: n, priced: n, changed: n}}`,
  where `priced` counts products with a price.
  """
  def sync_eshop_prices(now \\ DateTime.utc_now()) do
    listings =
      Repo.all(
        from l in StoreListing,
          where: l.store == :eshop_br and l.match in ^@priced and not is_nil(l.external_id)
      )

    listings
    |> Enum.chunk_every(Eshop.price_batch())
    |> Enum.reduce_while({:ok, %{listings: length(listings), priced: 0, changed: 0}}, fn chunk,
                                                                                         {:ok,
                                                                                          totals} ->
      case Eshop.prices(Enum.map(chunk, & &1.external_id)) do
        {:ok, prices} -> {:cont, {:ok, record_prices(chunk, prices, now, totals)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp record_prices(listings, prices, now, totals) do
    by_id = Map.new(prices, &{to_string(&1["title_id"]), &1})

    Enum.reduce(listings, totals, fn listing, totals ->
      case Map.fetch(by_id, listing.external_id) do
        {:ok, price} ->
          attrs = price_attrs(price)
          changed? = record_price(listing, attrs, now)

          %{
            totals
            | priced: totals.priced + if(attrs.regular_cents, do: 1, else: 0),
              changed: totals.changed + if(changed?, do: 1, else: 0)
          }

        :error ->
          totals
      end
    end)
  end

  defp record_price(listing, attrs, now) do
    {:ok, changed?} =
      Repo.transaction(fn ->
        latest =
          Repo.one(
            from p in StorePrice,
              where: p.listing_id == ^listing.id,
              order_by: [desc: p.first_seen_at],
              limit: 1,
              lock: "FOR UPDATE"
          )

        changed? = is_nil(latest) or Map.take(latest, Map.keys(attrs)) != attrs

        if changed? do
          %StorePrice{listing_id: listing.id}
          |> StorePrice.changeset(Map.merge(attrs, %{first_seen_at: now, last_seen_at: now}))
          |> Repo.insert!()
        else
          latest |> Ecto.Changeset.change(last_seen_at: now) |> Repo.update!()
        end

        listing
        |> Ecto.Changeset.change(sales_status: attrs.sales_status, checked_at: now)
        |> Repo.update!()

        changed?
      end)

    changed?
  end

  defp price_attrs(price) do
    discount = price["discount_price"]

    %{
      sales_status: price["sales_status"],
      regular_cents: cents(price["regular_price"]),
      discount_cents: cents(discount),
      discount_starts_at: datetime(discount && discount["start_datetime"]),
      discount_ends_at: datetime(discount && discount["end_datetime"]),
      currency: get_in(price, ["regular_price", "currency"]) || "BRL"
    }
  end

  defp cents(%{"raw_value" => raw}) when is_binary(raw),
    do: raw |> Decimal.new() |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()

  defp cents(_), do: nil

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, %DateTime{microsecond: {microsecond, _}} = datetime, _offset} ->
        %{datetime | microsecond: {microsecond, 6}}

      _ ->
        nil
    end
  end

  defp datetime(_), do: nil
end
