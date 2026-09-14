defmodule Dockd.Library do
  import Ecto.Query
  import Ecto.Changeset
  alias Dockd.{Repo, Accounts.User}
  alias Dockd.Library.{Entry, Ownership, ReleaseVeto}
  alias Dockd.Activity

  @doc "Lists entries for a user, preloading their games."
  def list_entries(%User{id: id}), do: Repo.all(from e in Entry, where: e.user_id == ^id, order_by: [asc: e.priority, asc: e.inserted_at], preload: [:game])
  @doc "Gets an entry for a user."
  def get_entry!(%User{id: id}, entry_id), do: Repo.one!(from e in Entry, where: e.id == ^entry_id and e.user_id == ^id, preload: [:game])
  @doc "Creates an entry and its added event atomically."
  def create_entry(%User{id: user_id}, attrs) do
    changeset = entry_changeset(%Entry{user_id: user_id}, Map.put(attrs, :user_id, user_id))
    Ecto.Multi.new() |> Ecto.Multi.insert(:entry, changeset) |> event_for(:added, user_id, attrs) |> Repo.transaction() |> result(:entry)
  end
  @doc "Updates an entry and records each state transition atomically."
  def update_entry(%User{id: user_id}, %Entry{user_id: ^user_id} = entry, attrs) do
    changeset = entry_changeset(entry, attrs)
    multi = Ecto.Multi.new() |> Ecto.Multi.update(:entry, changeset)
    multi = Enum.reduce([:purchase_intent, :play_state, :backlog], multi, fn field, acc ->
      if get_change(changeset, field), do: event_for(acc, event_type(field, get_change(changeset, field)), user_id, %{field: field, value: get_change(changeset, field)}), else: acc
    end)
    multi |> Repo.transaction() |> result(:entry)
  end
  @doc "Deletes an entry scoped to a user."
  def delete_entry(%User{id: user_id}, %Entry{user_id: user_id} = entry), do: Repo.delete(entry)
  @doc "Lists a user's ownership records."
  def list_ownerships(%User{id: id}), do: Repo.all(from o in Ownership, where: o.user_id == ^id, preload: [:release])
  @doc "Creates an ownership record."
  def create_ownership(%User{id: id}, attrs), do: %Ownership{user_id: id} |> ownership_changeset(Map.put(attrs, :user_id, id)) |> Repo.insert()
  @doc "Gets an ownership record scoped to a user."
  def get_ownership!(%User{id: id}, ownership_id), do: Repo.one!(from o in Ownership, where: o.id == ^ownership_id and o.user_id == ^id)
  @doc "Updates an ownership record scoped to a user."
  def update_ownership(%User{id: id}, %Ownership{user_id: id} = ownership, attrs), do: ownership |> ownership_changeset(attrs) |> Repo.update()
  @doc "Deletes an ownership record scoped to a user."
  def delete_ownership(%User{id: id}, %Ownership{user_id: id} = ownership), do: Repo.delete(ownership)
  @doc "Lists release vetoes for a user."
  def list_vetoes(%User{id: id}), do: Repo.all(from v in ReleaseVeto, where: v.user_id == ^id, preload: [:release])
  @doc "Creates a release veto and its event atomically."
  def create_veto(%User{id: user_id}, attrs) do
    cs = veto_changeset(%ReleaseVeto{user_id: user_id}, Map.put(attrs, :user_id, user_id))
    Ecto.Multi.new() |> Ecto.Multi.insert(:veto, cs) |> event_for(:vetoed, user_id, attrs) |> Repo.transaction() |> result(:veto)
  end
  @doc "Gets a release veto scoped to a user."
  def get_veto!(%User{id: id}, veto_id), do: Repo.one!(from v in ReleaseVeto, where: v.id == ^veto_id and v.user_id == ^id)
  @doc "Updates a release veto scoped to a user."
  def update_veto(%User{id: id}, %ReleaseVeto{user_id: id} = veto, attrs), do: veto |> veto_changeset(attrs) |> Repo.update()
  @doc "Deletes a release veto scoped to a user."
  def delete_veto(%User{id: id}, %ReleaseVeto{user_id: id} = veto), do: Repo.delete(veto)

  defp entry_changeset(entry, attrs), do: entry |> cast(attrs, [:user_id, :game_id, :purchase_intent, :play_state, :backlog, :priority, :media_preference, :target_price_cents, :currency, :owned_elsewhere, :owned_elsewhere_note, :duration_override_minutes, :pace_override, :notes]) |> validate_required([:user_id, :game_id]) |> validate_number(:target_price_cents, greater_than_or_equal_to: 0) |> validate_number(:duration_override_minutes, greater_than: 0) |> unique_constraint([:user_id, :game_id]) |> assoc_constraint(:game)
  defp ownership_changeset(o, attrs), do: o |> cast(attrs, [:user_id, :release_id, :ownership_type, :acquired_at, :purchase_id]) |> validate_required([:user_id, :release_id, :ownership_type, :acquired_at]) |> unique_constraint([:user_id, :release_id, :ownership_type])
  defp veto_changeset(v, attrs), do: v |> cast(attrs, [:user_id, :release_id, :reason]) |> validate_required([:user_id, :release_id]) |> unique_constraint([:user_id, :release_id])
  defp event_for(multi, type, user_id, attrs), do: Activity.append(multi, %{user_id: user_id, game_id: attrs[:game_id], release_id: attrs[:release_id], type: type, occurred_at: DateTime.utc_now(), payload: Map.new(attrs)})
  defp event_type(:purchase_intent, _), do: :intent_changed
  defp event_type(:play_state, :playing), do: :started
  defp event_type(:play_state, :paused), do: :paused
  defp event_type(:play_state, :finished), do: :finished
  defp event_type(:play_state, :abandoned), do: :abandoned
  defp event_type(:play_state, _), do: :resumed
  defp event_type(:backlog, :backlog), do: :backlogged
  defp event_type(:backlog, :active), do: :activated
  defp event_type(:backlog, _), do: :activated
  defp result({:ok, values}, key), do: {:ok, values[key]}
  defp result({:error, _op, changeset, _}, _), do: {:error, changeset}
end
