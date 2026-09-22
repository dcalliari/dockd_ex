defmodule DockdWeb.PurchasingController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Dockd.{Accounts, Library, Purchasing}
  alias Dockd.Library.ReleaseVeto
  alias Dockd.Purchasing.{PriceObservation, Purchase}
  alias DockdWeb.ApiSchemas
  plug OpenApiSpex.Plug.CastAndValidate, render_error: DockdWeb.ApiErrorRenderer

  operation(:index_purchases,
    summary: "List purchases",
    parameters: [game_id: [in: :query, required: false, type: :string]],
    responses: %{200 => {"Purchases", "application/json", ApiSchemas.PurchasingListResponse}}
  )

  operation(:index_observations,
    summary: "List price observations",
    parameters: [release_id: [in: :path, required: true, type: :string]],
    responses: %{
      200 => {"Price observations", "application/json", ApiSchemas.PurchasingListResponse}
    }
  )

  operation(:index_vetoes,
    summary: "List release vetoes",
    responses: %{200 => {"Vetoes", "application/json", ApiSchemas.PurchasingListResponse}}
  )

  operation(:delete_veto,
    summary: "Remove a release veto",
    parameters: [id: [in: :path, required: true, type: :string]],
    responses: %{204 => {nil, nil, nil}}
  )

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

  def index_purchases(conn, params) do
    user = Accounts.default_owner()

    purchases =
      case params[:game_id] || params["game_id"] do
        nil -> Purchasing.list_purchases(user)
        game_id -> Purchasing.list_purchases_for_game(user, game_id)
      end

    json(conn, %{data: Enum.map(purchases, &purchase_json/1)})
  end

  def index_observations(conn, params) do
    observations =
      Purchasing.list_price_observations(
        Accounts.default_owner(),
        release_param(params, :release_id)
      )

    json(conn, %{data: Enum.map(observations, &observation_json/1)})
  end

  def index_vetoes(conn, _),
    do: json(conn, %{data: Enum.map(Library.list_vetoes(Accounts.default_owner()), &veto_json/1)})

  def delete_veto(conn, params) do
    user = Accounts.default_owner()
    veto = Library.get_veto!(user, params[:id] || params["id"])
    {:ok, _} = Library.delete_veto(user, veto)
    send_resp(conn, :no_content, "")
  end

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

  defp body_attrs(conn) do
    (Map.get(conn.body_params, "data") || Map.get(conn.body_params, :data) || conn.body_params)
    |> then(fn attrs -> if is_struct(attrs), do: Map.from_struct(attrs), else: attrs end)
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp purchase_json(%Purchase{} = purchase),
    do:
      Map.take(purchase, [
        :id,
        :user_id,
        :release_id,
        :format,
        :price_cents,
        :currency,
        :store_credit_used_cents,
        :purchased_at,
        :is_preorder,
        :retailer
      ])

  defp observation_json(%PriceObservation{} = observation),
    do:
      Map.take(observation, [
        :id,
        :user_id,
        :release_id,
        :format,
        :price_cents,
        :currency,
        :observed_at,
        :source
      ])

  defp veto_json(%ReleaseVeto{} = veto),
    do: Map.take(veto, [:id, :user_id, :release_id, :reason, :inserted_at])

  defp respond(conn, {:ok, value}),
    do:
      conn
      |> put_status(:created)
      |> json(%{data: value |> Map.from_struct() |> Map.drop([:__meta__, :user, :release])})

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
