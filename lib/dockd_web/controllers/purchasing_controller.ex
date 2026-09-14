defmodule DockdWeb.PurchasingController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Dockd.{Accounts, Library, Purchasing}
  alias DockdWeb.ApiSchemas
  plug OpenApiSpex.Plug.CastAndValidate, render_error: DockdWeb.ApiErrorRenderer

  operation(:create_observation,
    summary: "Record a price observation",
    parameters: [release_id: [in: :path, required: true, type: :string]],
    request_body:
      {"Observation", "application/json", ApiSchemas.PurchasingRequest, [required: true]},
    responses: %{
      201 => {"Observation", "application/json", ApiSchemas.PurchasingResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:create_purchase,
    summary: "Register a purchase",
    parameters: [release_id: [in: :path, required: true, type: :string]],
    request_body:
      {"Purchase", "application/json", ApiSchemas.PurchasingRequest, [required: true]},
    responses: %{
      201 => {"Purchase", "application/json", ApiSchemas.PurchasingResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:create_veto,
    summary: "Veto a release",
    parameters: [release_id: [in: :path, required: true, type: :string]],
    request_body: {"Veto", "application/json", ApiSchemas.PurchasingRequest, [required: true]},
    responses: %{
      201 => {"Veto", "application/json", ApiSchemas.PurchasingResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  def create_observation(conn, params) do
    attrs = body_attrs(conn) |> Map.put("release_id", release_param(params, :release_id))
    respond(conn, Purchasing.create_price_observation(Accounts.default_owner(), attrs))
  end

  def create_purchase(conn, params) do
    attrs = body_attrs(conn) |> Map.put("release_id", release_param(params, :release_id))
    respond(conn, Purchasing.create_purchase(Accounts.default_owner(), attrs))
  end

  def create_veto(conn, params) do
    attrs = body_attrs(conn) |> Map.put("release_id", release_param(params, :release_id))
    respond(conn, Library.create_veto(Accounts.default_owner(), attrs))
  end

  defp release_param(params, key),
    do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp body_attrs(conn),
    do:
      Map.get(conn.body_params, "data", conn.body_params)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

  defp respond(conn, {:ok, value}),
    do: conn |> put_status(:created) |> json(%{data: Map.from_struct(value)})

  defp respond(conn, {:error, changeset}),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        error: %{
          type: "validation",
          details: Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
        }
      })
end
