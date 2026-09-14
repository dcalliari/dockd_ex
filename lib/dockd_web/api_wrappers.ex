defmodule DockdWeb.ApiSchemas.GameRequest do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "GameRequest",
    type: :object,
    required: [:game],
    properties: %{game: DockdWeb.ApiSchemas.GameAttributes}
  })
end

defmodule DockdWeb.ApiSchemas.ReleaseRequest do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ReleaseRequest",
    type: :object,
    required: [:release],
    properties: %{release: DockdWeb.ApiSchemas.ReleaseAttributes}
  })
end

defmodule DockdWeb.ApiSchemas.GameResponse do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "GameResponse",
    type: :object,
    required: [:data],
    properties: %{data: DockdWeb.ApiSchemas.Game}
  })
end

defmodule DockdWeb.ApiSchemas.GameListResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GameListResponse",
    type: :object,
    required: [:data],
    properties: %{data: %Schema{type: :array, items: DockdWeb.ApiSchemas.Game}}
  })
end

defmodule DockdWeb.ApiSchemas.ReleaseResponse do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ReleaseResponse",
    type: :object,
    required: [:data],
    properties: %{data: DockdWeb.ApiSchemas.Release}
  })
end

defmodule DockdWeb.ApiSchemas.ReleaseListResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReleaseListResponse",
    type: :object,
    required: [:data],
    properties: %{data: %Schema{type: :array, items: DockdWeb.ApiSchemas.Release}}
  })
end
