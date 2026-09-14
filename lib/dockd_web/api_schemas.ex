defmodule DockdWeb.ApiSchemas.Error do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ValidationError",
    type: :object,
    properties: %{
      error: %Schema{
        type: :object,
        required: [:type, :details],
        properties: %{
          type: %Schema{type: :string, enum: ["validation"]},
          details: %Schema{
            type: :object,
            additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
          }
        }
      }
    },
    required: [:error]
  })
end

defmodule DockdWeb.ApiSchemas.Release do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Release",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      game_id: %Schema{type: :string, format: :uuid},
      platform: %Schema{type: :string, enum: ["switch", "switch_2"]},
      edition: %Schema{type: :string, nullable: true},
      release_date: %Schema{type: :string, format: :date, nullable: true},
      physical_available: %Schema{type: :boolean},
      digital_available: %Schema{type: :boolean}
    },
    required: [:id, :game_id, :platform, :physical_available, :digital_available]
  })
end

defmodule DockdWeb.ApiSchemas.Game do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Game",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string},
      slug: %Schema{type: :string},
      cover_url: %Schema{type: :string, nullable: true},
      developer: %Schema{type: :string, nullable: true},
      publisher: %Schema{type: :string, nullable: true},
      availability: %Schema{
        type: :string,
        enum: ["nintendo_exclusive", "switch2_exclusive", "multiplatform"]
      },
      other_platforms: %Schema{type: :array, items: %Schema{type: :string}},
      estimated_duration_minutes: %Schema{type: :integer, minimum: 1, nullable: true},
      pace: %Schema{type: :string, enum: ["relaxing", "normal", "demanding"], nullable: true},
      play_mode: %Schema{type: :string, enum: ["solo", "multi", "both"], nullable: true},
      releases: %Schema{type: :array, items: DockdWeb.ApiSchemas.Release}
    },
    required: [:id, :title, :slug, :availability, :other_platforms, :releases]
  })
end

defmodule DockdWeb.ApiSchemas.GameAttributes do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "GameAttributes",
    type: :object,
    properties: %{
      title: %Schema{type: :string},
      slug: %Schema{type: :string},
      cover_url: %Schema{type: :string},
      developer: %Schema{type: :string},
      publisher: %Schema{type: :string},
      availability: %Schema{
        type: :string,
        enum: ["nintendo_exclusive", "switch2_exclusive", "multiplatform"]
      },
      other_platforms: %Schema{type: :array, items: %Schema{type: :string}},
      estimated_duration_minutes: %Schema{type: :integer, minimum: 1},
      pace: %Schema{type: :string, enum: ["relaxing", "normal", "demanding"]},
      play_mode: %Schema{type: :string, enum: ["solo", "multi", "both"]}
    }
  })
end

defmodule DockdWeb.ApiSchemas.ReleaseAttributes do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReleaseAttributes",
    type: :object,
    properties: %{
      platform: %Schema{type: :string, enum: ["switch", "switch_2"]},
      edition: %Schema{type: :string},
      release_date: %Schema{type: :string, format: :date},
      physical_available: %Schema{type: :boolean},
      digital_available: %Schema{type: :boolean}
    }
  })
end

defmodule DockdWeb.ApiSchemas do
  @moduledoc false
  alias OpenApiSpex.Schema

  def envelope(schema), do: %Schema{type: :object, required: [:data], properties: %{data: schema}}
  def list_envelope(schema), do: envelope(%Schema{type: :array, items: schema})
  def request(schema), do: %Schema{type: :object, required: [:game], properties: %{game: schema}}

  def release_request(schema),
    do: %Schema{type: :object, required: [:release], properties: %{release: schema}}
end
