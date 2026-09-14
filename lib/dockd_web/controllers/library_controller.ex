defmodule DockdWeb.LibraryController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Dockd.Accounts
  alias Dockd.Library
  alias Dockd.Library.{Entry, Ownership}
  alias DockdWeb.ApiSchemas

  plug OpenApiSpex.Plug.CastAndValidate, render_error: DockdWeb.ApiErrorRenderer

  operation(:index,
    summary: "List library entries",
    responses: %{200 => {"Entries", "application/json", ApiSchemas.EntryListResponse}}
  )

  operation(:show,
    summary: "Show library entry",
    parameters: [id: [in: :path, required: true, type: :string]],
    responses: %{200 => {"Entry", "application/json", ApiSchemas.EntryResponse}}
  )

  operation(:create,
    summary: "Add library entry",
    request_body: {"Entry", "application/json", ApiSchemas.EntryRequest, [required: true]},
    responses: %{
      201 => {"Entry", "application/json", ApiSchemas.EntryResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:update,
    summary: "Update library entry",
    parameters: [id: [in: :path, required: true, type: :string]],
    request_body: {"Entry", "application/json", ApiSchemas.EntryRequest, [required: true]},
    responses: %{
      200 => {"Entry", "application/json", ApiSchemas.EntryResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:delete,
    summary: "Remove library entry",
    parameters: [id: [in: :path, required: true, type: :string]],
    responses: %{204 => {nil, nil, nil}}
  )

  def index(conn, _),
    do:
      json(conn, %{data: Enum.map(Library.list_entries(Accounts.default_owner()), &entry_json/1)})

  def show(conn, %{"id" => id}),
    do: render_entry(conn, Library.get_entry!(Accounts.default_owner(), id))

  def create(conn, _) do
    case Library.create_entry(Accounts.default_owner(), attrs(conn, "entry")) do
      {:ok, entry} ->
        conn
        |> put_status(:created)
        |> render_entry(Library.get_entry!(Accounts.default_owner(), entry.id))

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id}) do
    user = Accounts.default_owner()
    entry = Library.get_entry!(user, id)

    case Library.update_entry(user, entry, attrs(conn, "entry")) do
      {:ok, entry} -> render_entry(conn, entry)
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Accounts.default_owner()
    :ok = Library.delete_entry(user, Library.get_entry!(user, id)) |> normalize_delete()
    send_resp(conn, :no_content, "")
  end

  defp normalize_delete({:ok, _}), do: :ok
  defp normalize_delete(error), do: raise("delete failed: #{inspect(error)}")
  defp render_entry(conn, entry), do: json(conn, %{data: entry_json(entry)})

  defp entry_json(%Entry{} = entry),
    do:
      Map.take(entry, [
        :id,
        :user_id,
        :game_id,
        :purchase_intent,
        :play_state,
        :backlog,
        :priority,
        :media_preference,
        :target_price_cents,
        :currency,
        :owned_elsewhere,
        :owned_elsewhere_note,
        :notes
      ])

  defp attrs(conn, key),
    do: Map.get(conn.body_params, key, %{}) |> Map.delete(:user_id) |> Map.delete("user_id")

  defp validation_error(conn, changeset),
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

defmodule DockdWeb.OwnershipController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Dockd.Accounts
  alias Dockd.Library
  alias Dockd.Library.Ownership
  alias DockdWeb.ApiSchemas
  plug OpenApiSpex.Plug.CastAndValidate, render_error: DockdWeb.ApiErrorRenderer

  operation(:index,
    summary: "List ownerships",
    responses: %{200 => {"Ownerships", "application/json", ApiSchemas.OwnershipListResponse}}
  )

  operation(:show,
    summary: "Show ownership",
    parameters: [id: [in: :path, required: true, type: :string]],
    responses: %{200 => {"Ownership", "application/json", ApiSchemas.OwnershipResponse}}
  )

  operation(:create,
    summary: "Add ownership",
    request_body:
      {"Ownership", "application/json", ApiSchemas.OwnershipRequest, [required: true]},
    responses: %{
      201 => {"Ownership", "application/json", ApiSchemas.OwnershipResponse},
      422 => {"Validation error", "application/json", ApiSchemas.Error}
    }
  )

  operation(:update,
    summary: "Update ownership",
    parameters: [id: [in: :path, required: true, type: :string]],
    request_body:
      {"Ownership", "application/json", ApiSchemas.OwnershipRequest, [required: true]},
    responses: %{200 => {"Ownership", "application/json", ApiSchemas.OwnershipResponse}}
  )

  operation(:delete,
    summary: "Remove ownership",
    parameters: [id: [in: :path, required: true, type: :string]],
    responses: %{204 => {nil, nil, nil}}
  )

  def index(conn, _),
    do:
      json(conn, %{
        data: Enum.map(Library.list_ownerships(Accounts.default_owner()), &ownership_json/1)
      })

  def show(conn, %{"id" => id}),
    do: render_ownership(conn, Library.get_ownership!(Accounts.default_owner(), id))

  def create(conn, _), do: save(conn, :create, nil)

  def update(conn, %{"id" => id}),
    do: save(conn, :update, Library.get_ownership!(Accounts.default_owner(), id))

  def delete(conn, %{"id" => id}),
    do:
      Library.delete_ownership(
        Accounts.default_owner(),
        Library.get_ownership!(Accounts.default_owner(), id)
      )
      |> then(fn _ -> send_resp(conn, :no_content, "") end)

  defp save(conn, :create, _) do
    case Library.create_ownership(Accounts.default_owner(), body(conn)) do
      {:ok, o} -> conn |> put_status(:created) |> render_ownership(o)
      {:error, cs} -> error(conn, cs)
    end
  end

  defp save(conn, :update, o) do
    case Library.update_ownership(Accounts.default_owner(), o, body(conn)) do
      {:ok, o} -> render_ownership(conn, o)
      {:error, cs} -> error(conn, cs)
    end
  end

  defp body(conn), do: Map.get(conn.body_params, "ownership", %{})
  defp render_ownership(conn, o), do: json(conn, %{data: ownership_json(o)})

  defp ownership_json(%Ownership{} = o),
    do: Map.take(o, [:id, :user_id, :release_id, :ownership_type, :acquired_at, :purchase_id])

  defp error(conn, cs),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        error: %{
          type: "validation",
          details: Ecto.Changeset.traverse_errors(cs, fn {m, _} -> m end)
        }
      })
end
