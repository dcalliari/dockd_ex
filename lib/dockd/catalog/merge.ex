defmodule Dockd.Catalog.Merge do
  @moduledoc """
  The steps of `Dockd.Catalog.merge_games/3`, run inside its transaction.

  A release of the absorbed game changes owner when the winner has no release of the
  same platform and edition. When it has, everything pointing to the absorbed release
  moves to the winner's: purchases, price observations and events as they are; a
  repeated ownership (same account and media) stays one, with the earliest date and
  the purchase kept; a repeated veto stays one; an accepted store listing wins over
  one in review, and keeps its price history.
  """
  import Ecto.Query
  alias Dockd.Activity.Event
  alias Dockd.Catalog.{Game, GameLink, Release}
  alias Dockd.Library.{Entry, Ownership, ReleaseVeto}
  alias Dockd.Pricing.StoreListing
  alias Dockd.Purchasing.{PriceObservation, Purchase}

  @priorities [:low, :normal, :high]

  def releases(repo, winner_id, loser_id) do
    now = DateTime.utc_now()

    for release <- repo.all(from r in Release, where: r.game_id == ^loser_id) do
      case repo.get_by(Release,
             game_id: winner_id,
             platform: release.platform,
             edition: release.edition
           ) do
        nil ->
          repo.update_all(from(r in Release, where: r.id == ^release.id),
            set: [game_id: winner_id, updated_at: now]
          )

        target ->
          fold(repo, release.id, target.id)
      end
    end

    {:ok, :releases}
  end

  defp fold(repo, from_id, into_id) do
    ownerships(repo, from_id, into_id)

    for schema <- [Purchase, PriceObservation, Event],
        do:
          repo.update_all(from(x in schema, where: x.release_id == ^from_id),
            set: [release_id: into_id]
          )

    vetoed = from v in ReleaseVeto, where: v.release_id == ^into_id, select: v.user_id

    repo.delete_all(
      from v in ReleaseVeto, where: v.release_id == ^from_id and v.user_id in subquery(vetoed)
    )

    repo.update_all(from(v in ReleaseVeto, where: v.release_id == ^from_id),
      set: [release_id: into_id]
    )

    listing(repo, from_id, into_id)
    repo.delete_all(from r in Release, where: r.id == ^from_id)
  end

  defp ownerships(repo, from_id, into_id) do
    kept = repo.all(from o in Ownership, where: o.release_id == ^into_id)

    for moved <- repo.all(from o in Ownership, where: o.release_id == ^from_id) do
      case Enum.find(
             kept,
             &(&1.user_id == moved.user_id and &1.ownership_type == moved.ownership_type)
           ) do
        nil ->
          repo.update_all(from(o in Ownership, where: o.id == ^moved.id),
            set: [release_id: into_id]
          )

        same ->
          repo.delete_all(from o in Ownership, where: o.id == ^moved.id)

          repo.update_all(from(o in Ownership, where: o.id == ^same.id),
            set: [
              purchase_id: same.purchase_id || moved.purchase_id,
              acquired_at: Enum.min([same.acquired_at, moved.acquired_at], DateTime)
            ]
          )
      end
    end
  end

  # Two listings of the same release cannot share an nsuid (unique per store), so the
  # one left behind sells another product and its prices go with it.
  defp listing(repo, from_id, into_id) do
    kept = repo.get_by(StoreListing, release_id: into_id, store: :eshop_br)
    moved = repo.get_by(StoreListing, release_id: from_id, store: :eshop_br)

    cond do
      is_nil(moved) ->
        :ok

      is_nil(kept) ->
        move_listing(repo, moved, into_id)

      kept.match in [:review, :rejected] and moved.match in [:auto, :confirmed] ->
        repo.delete_all(from l in StoreListing, where: l.id == ^kept.id)
        move_listing(repo, moved, into_id)

      true ->
        repo.delete_all(from l in StoreListing, where: l.id == ^moved.id)
    end
  end

  defp move_listing(repo, listing, release_id),
    do:
      repo.update_all(from(l in StoreListing, where: l.id == ^listing.id),
        set: [release_id: release_id]
      )

  @doc """
  One entry per account: the state of the entry changed last (intent, play state,
  backlog), the higher priority, the lower target price and both notes.
  """
  def entries(repo, winner_id, loser_id) do
    for moved <- repo.all(from e in Entry, where: e.game_id == ^loser_id) do
      case repo.get_by(Entry, game_id: winner_id, user_id: moved.user_id) do
        nil ->
          repo.update_all(from(e in Entry, where: e.id == ^moved.id), set: [game_id: winner_id])

        kept ->
          repo.delete_all(from e in Entry, where: e.id == ^moved.id)

          repo.update_all(from(e in Entry, where: e.id == ^kept.id),
            set: joined_entry(kept, moved)
          )
      end
    end

    {:ok, :entries}
  end

  defp joined_entry(kept, moved) do
    newer = if DateTime.compare(moved.updated_at, kept.updated_at) == :gt, do: moved, else: kept

    [
      purchase_intent: newer.purchase_intent,
      play_state: newer.play_state,
      backlog: newer.backlog,
      priority:
        Enum.max_by(
          [kept.priority, moved.priority],
          &Enum.find_index(@priorities, fn p -> p == &1 end)
        ),
      target_price_cents:
        [kept.target_price_cents, moved.target_price_cents]
        |> Enum.reject(&is_nil/1)
        |> Enum.min(fn -> nil end),
      owned_elsewhere: kept.owned_elsewhere or moved.owned_elsewhere,
      owned_elsewhere_note: kept.owned_elsewhere_note || moved.owned_elsewhere_note,
      notes:
        [kept.notes, moved.notes]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.uniq()
        |> join_notes(),
      updated_at: Enum.max([kept.updated_at, moved.updated_at], DateTime)
    ]
  end

  defp join_notes([]), do: nil
  defp join_notes(notes), do: Enum.join(notes, "\n")

  @doc """
  The game's history and links follow the winner, the loser goes, and its IGDB id
  becomes the winner's link. A link that asked about the loser gets the answer.
  """
  def game(repo, winner_id, %Game{} = loser, link) do
    repo.update_all(from(e in Event, where: e.game_id == ^loser.id), set: [game_id: winner_id])
    repo.update_all(from(l in GameLink, where: l.game_id == ^loser.id), set: [game_id: winner_id])
    repo.delete_all(from g in Game, where: g.id == ^loser.id)

    if loser.igdb_id do
      now = DateTime.utc_now()

      repo.insert_all(
        GameLink,
        [
          %{
            id: Ecto.UUID.generate(),
            igdb_id: loser.igdb_id,
            game_id: winner_id,
            kind: link.kind,
            match: link.match,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: [set: [game_id: winner_id, match: link.match, updated_at: now]],
        conflict_target: :igdb_id
      )
    end

    {:ok, :game}
  end
end
