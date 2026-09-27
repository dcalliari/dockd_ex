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
    latest =
      from p in StorePrice,
        distinct: p.listing_id,
        order_by: [asc: p.listing_id, desc: p.first_seen_at]

    Repo.one(
      from l in StoreListing,
        join: p in subquery(latest),
        on: p.listing_id == l.id,
        where:
          l.release_id == ^release_id and l.match in ^@priced and not is_nil(p.regular_cents),
        select: p
    )
    |> case do
      nil -> nil
      price -> store_current_price(price, now)
    end
  end

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
    prices = run_step("preços", fn -> sync_eshop_prices(now) end)

    case prices do
      {:ok, %{listings: listings, priced: 0}} when listings > 0 ->
        Logger.error("eShop: nenhum preço para #{listings} produtos; a API pode ter mudado")

      _ ->
        :ok
    end

    %{match: match, prices: prices}
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
  with up to three candidates. A release without any candidate gets no listing. Both
  are searched again on the next run, since the store lists games before launch.
  """
  def match_eshop do
    if Eshop.configured?() do
      pending = pending_releases()
      releases = Enum.map(pending, &elem(&1, 0))

      match_games(
        Enum.group_by(pending, &elem(&1, 0).game),
        alternative_names(releases)
      )
    else
      {:error, :not_configured}
    end
  end

  # A search failure (a rotated key answers 403) stops the matching, not the prices.
  defp match_games(releases_by_game, alternative_names) do
    Enum.reduce_while(releases_by_game, {:ok, %{auto: 0, review: 0, none: 0}}, fn
      {game, releases}, {:ok, counts} ->
        titles =
          EshopMatch.search_titles(game.title, Map.get(alternative_names, game.igdb_id, []))

        case match_game(titles, releases) do
          {:ok, decisions} -> {:cont, {:ok, count(counts, decisions)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  # Each release with its listing in review, or nil.
  defp pending_releases do
    Repo.all(
      from r in Release,
        join: g in Game,
        on: g.id == r.game_id,
        left_join: l in StoreListing,
        on: l.release_id == r.id and l.store == :eshop_br,
        where: is_nil(l.id) or l.match == :review,
        order_by: [asc: g.title, asc: r.platform],
        preload: [game: g],
        select: {r, l}
    )
  end

  defp alternative_names(releases) do
    ids = releases |> Enum.map(& &1.game.igdb_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids != [] and Dockd.IGDB.configured?() do
      ids
      |> Enum.chunk_every(500)
      |> Enum.flat_map(&igdb_games/1)
      |> Map.new(fn game ->
        {game["id"], Enum.map(game["alternative_names"] || [], & &1["name"])}
      end)
    else
      %{}
    end
  end

  # Without IGDB the game's own title is still searched.
  defp igdb_games(ids) do
    case Dockd.IGDB.get_games(ids) do
      {:ok, %{body: games}} when is_list(games) -> games
      _ -> []
    end
  end

  defp match_game(titles, pending) do
    platforms = pending |> Enum.map(&elem(&1, 0).platform) |> Enum.uniq()
    queries = for locale <- @locales, title <- titles, do: {locale, title}

    with {:ok, hits} <- search_until_settled(queries, titles, platforms, []) do
      {:ok,
       Enum.map(pending, fn {release, listing} ->
         save_decision(release, listing, EshopMatch.candidates(titles, hits, release.platform))
       end)}
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

  defp save_decision(release, listing, candidates) do
    attrs =
      case EshopMatch.decide(candidates) do
        :none ->
          nil

        {:auto, %{hit: hit}} ->
          %{match: :auto, external_id: hit["nsuid"], title: hit["title"], candidates: []}

        {:review, candidates} ->
          %{
            match: :review,
            external_id: nil,
            title: nil,
            candidates: Enum.map(candidates, &candidate/1)
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

  defp candidate(%{hit: hit, class: class}),
    do: %{
      "external_id" => hit["nsuid"],
      "title" => hit["title"],
      "class" => Atom.to_string(class)
    }

  defp count(counts, decisions),
    do: Enum.reduce(decisions, counts, &Map.update!(&2, &1, fn n -> n + 1 end))

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
