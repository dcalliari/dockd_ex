defmodule DockdWeb.ApiSpec do
  @moduledoc """
  OpenAPI document generated from controller operation declarations.

  To add a route, declare `operation :action` in its controller, add its schemas
  to the operation, and expose the route in `DockdWeb.Router`. The router guard
  test ensures the operation cannot be forgotten.

  Every `/api/v1` route answers for the account of the bearer token.
  """

  alias DockdWeb.Router
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      openapi: "3.0.3",
      info: %Info{title: "Dockd API", version: "0.1.0"},
      servers: [%Server{url: "http://localhost:4000"}],
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "token" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            description: "Token da conta, copiado no menu da conta. Um novo substitui o anterior."
          }
        }
      },
      security: [%{"token" => []}]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  def export do
    File.mkdir_p!("priv/static")
    json = spec() |> OpenApiSpex.OpenApi.to_map() |> Jason.encode_to_iodata!()
    File.write!("priv/static/openapi.json", json)
  end
end
