defmodule DockdWeb.ApiErrorRenderer do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, errors) do
    details =
      errors
      |> List.wrap()
      |> Enum.reduce(%{}, fn error, acc ->
        key = error_key(error)
        Map.update(acc, key, [error_message(error)], &[error_message(error) | &1])
      end)
      |> Map.new(fn {key, messages} -> {key, Enum.reverse(messages)} end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(422, Jason.encode!(%{error: %{type: "validation", details: details}}))
  end

  defp error_key(%{validation: :required, path: [field | _]}), do: to_string(field)
  defp error_key(%{path: [field | _]}), do: to_string(field)
  defp error_key(_), do: "base"

  defp error_message(%{reason: reason}), do: inspect(reason)
  defp error_message(error), do: inspect(error)
end
