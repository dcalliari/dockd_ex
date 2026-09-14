defmodule DockdWeb.ApiSchemas.IGDBError do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "IGDBError",
    type: :object,
    required: [:error],
    properties: %{
      error: %Schema{
        type: :object,
        required: [:type],
        properties: %{type: %Schema{type: :string}, details: %Schema{type: :string}}
      }
    }
  })
end

defmodule DockdWeb.ApiSchemas.IGDBSearchResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "IGDBSearchResponse",
    type: :object,
    required: [:data],
    properties: %{
      data: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}}
    }
  })
end

defmodule DockdWeb.ApiSchemas.IGDBSyncResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "IGDBSyncResponse",
    type: :object,
    required: [:data],
    properties: %{data: %Schema{type: :object, additionalProperties: true}}
  })
end

defmodule DockdWeb.ApiSchemas.IGDBMatchResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "IGDBMatchResponse",
    type: :object,
    required: [:data],
    properties: %{data: %Schema{type: :object, additionalProperties: true}}
  })
end
