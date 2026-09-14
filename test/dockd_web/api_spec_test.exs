defmodule DockdWeb.ApiSpecTest do
  use ExUnit.Case, async: true

  alias DockdWeb.{ApiSpec, Router}

  test "generated specification is complete and serializable" do
    spec = ApiSpec.spec()
    assert spec.openapi == "3.0.3"
    assert {:ok, _json} = Jason.encode(ApiSpec.spec() |> OpenApiSpex.OpenApi.to_map())
    assert Map.has_key?(spec.components.schemas, "ValidationError")
  end

  test "every versioned API route has an operation" do
    spec = ApiSpec.spec()

    for route <- Router.__routes__(), String.starts_with?(route.path, "/api/v1") do
      path = String.replace(route.path, ~r/:([a-z_]+)/, "{\\1}")
      operation = spec.paths |> Map.get(path) |> Map.get(route.verb)

      assert operation && operation.operationId,
             "#{route.verb} #{route.path} is missing from the generated OpenAPI document"
    end
  end
end
