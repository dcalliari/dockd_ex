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
      igdb_id: %Schema{type: :integer, nullable: true},
      synced_at: %Schema{type: :string, format: :date_time, nullable: true},
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

defmodule DockdWeb.ApiSchemas.Entry do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Entry",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      game_id: %Schema{type: :string, format: :uuid},
      purchase_intent: %Schema{type: :string},
      play_state: %Schema{type: :string},
      backlog: %Schema{type: :string},
      priority: %Schema{type: :string},
      media_preference: %Schema{type: :string},
      target_price_cents: %Schema{type: :integer, nullable: true},
      currency: %Schema{type: :string},
      owned_elsewhere: %Schema{type: :boolean},
      owned_elsewhere_note: %Schema{type: :string, nullable: true},
      notes: %Schema{type: :string, nullable: true}
    },
    required: [:id, :user_id, :game_id]
  })
end

defmodule DockdWeb.ApiSchemas.Ownership do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Ownership",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      release_id: %Schema{type: :string, format: :uuid},
      ownership_type: %Schema{type: :string},
      acquired_at: %Schema{type: :string, format: :date_time},
      purchase_id: %Schema{type: :string, format: :uuid, nullable: true}
    },
    required: [:id, :user_id, :release_id, :ownership_type, :acquired_at]
  })
end

defmodule DockdWeb.ApiSchemas.EntryAttributes do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EntryAttributes",
    type: :object,
    properties: %{
      game_id: %Schema{type: :string, format: :uuid},
      purchase_intent: %Schema{type: :string},
      play_state: %Schema{type: :string},
      backlog: %Schema{type: :string},
      priority: %Schema{type: :string},
      media_preference: %Schema{type: :string},
      target_price_cents: %Schema{type: :integer},
      currency: %Schema{type: :string},
      owned_elsewhere: %Schema{type: :boolean},
      owned_elsewhere_note: %Schema{type: :string},
      notes: %Schema{type: :string}
    }
  })
end

defmodule DockdWeb.ApiSchemas.OwnershipAttributes do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OwnershipAttributes",
    type: :object,
    properties: %{
      release_id: %Schema{type: :string, format: :uuid},
      ownership_type: %Schema{type: :string},
      acquired_at: %Schema{type: :string, format: :date_time},
      purchase_id: %Schema{type: :string, format: :uuid}
    }
  })
end

defmodule DockdWeb.ApiSchemas.EntryRequest do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "EntryRequest",
    type: :object,
    required: [:entry],
    properties: %{entry: DockdWeb.ApiSchemas.EntryAttributes}
  })
end

defmodule DockdWeb.ApiSchemas.OwnershipRequest do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "OwnershipRequest",
    type: :object,
    required: [:ownership],
    properties: %{ownership: DockdWeb.ApiSchemas.OwnershipAttributes}
  })
end

defmodule DockdWeb.ApiSchemas.EntryResponse do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "EntryResponse",
    type: :object,
    required: [:data],
    properties: %{data: DockdWeb.ApiSchemas.Entry}
  })
end

defmodule DockdWeb.ApiSchemas.EntryListResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "EntryListResponse",
    type: :object,
    required: [:data],
    properties: %{data: %Schema{type: :array, items: DockdWeb.ApiSchemas.Entry}}
  })
end

defmodule DockdWeb.ApiSchemas.OwnershipResponse do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "OwnershipResponse",
    type: :object,
    required: [:data],
    properties: %{data: DockdWeb.ApiSchemas.Ownership}
  })
end

defmodule DockdWeb.ApiSchemas.OwnershipListResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OwnershipListResponse",
    type: :object,
    required: [:data],
    properties: %{data: %Schema{type: :array, items: DockdWeb.ApiSchemas.Ownership}}
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
