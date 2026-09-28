defmodule Dockd.Pricing.CurrentPrice do
  @moduledoc """
  The eShop price a release goes for now, shaped like a price observation so a screen
  reads either one: `price_cents`, `currency`, `observed_at` (the store's
  `last_seen_at`, so the same staleness rule applies), `source`, `format` and
  `release_id`. `lowest_since` is set only when `price_cents` ties or beats every
  price the sync has ever recorded for the listing, to the date that history began
  (not when the low started, since the history itself is short).
  """
  @enforce_keys [:price_cents, :currency, :observed_at]
  defstruct [
    :price_cents,
    :currency,
    :observed_at,
    :release_id,
    source: "eShop",
    format: :digital,
    regular_cents: nil,
    discount_ends_at: nil,
    sales_status: nil,
    lowest_since: nil
  ]
end
