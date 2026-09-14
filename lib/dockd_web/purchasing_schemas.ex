defmodule DockdWeb.ApiSchemas.PurchasingRequest do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PurchasingRequest",
    type: :object,
    properties: %{
      format: %Schema{type: :string, enum: ["physical", "digital"]},
      price_cents: %Schema{type: :integer, minimum: 0},
      currency: %Schema{type: :string},
      observed_at: %Schema{type: :string, format: :date_time},
      purchased_at: %Schema{type: :string, format: :date_time},
      source: %Schema{type: :string},
      retailer: %Schema{type: :string},
      store_credit_used_cents: %Schema{type: :integer, minimum: 0},
      is_preorder: %Schema{type: :boolean},
      reason: %Schema{type: :string}
    }
  })
end

defmodule DockdWeb.ApiSchemas.PurchasingResponse do
  @moduledoc false
  require OpenApiSpex
  OpenApiSpex.schema(%{title: "PurchasingResponse", type: :object, additionalProperties: true})
end
