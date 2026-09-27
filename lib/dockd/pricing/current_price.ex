defmodule Dockd.Pricing.CurrentPrice do
  @moduledoc """
  The eShop price a release goes for now, shaped like a price observation so a screen
  reads either one: `price_cents`, `currency`, `observed_at` (the store's
  `last_seen_at`, so the same staleness rule applies), `source` and `format`.
  """
  @enforce_keys [:price_cents, :currency, :observed_at]
  defstruct [
    :price_cents,
    :currency,
    :observed_at,
    source: "eShop",
    format: :digital,
    regular_cents: nil,
    discount_ends_at: nil,
    sales_status: nil
  ]
end
