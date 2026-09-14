defmodule DockdWeb.ApiSchemas.PurchasingRequest do
  @moduledoc false
  require OpenApiSpex
  OpenApiSpex.schema(%{title: "PurchasingRequest", type: :object, additionalProperties: true})
end

defmodule DockdWeb.ApiSchemas.PurchasingResponse do
  @moduledoc false
  require OpenApiSpex
  OpenApiSpex.schema(%{title: "PurchasingResponse", type: :object, additionalProperties: true})
end
