defmodule Dockd.Accounts.UserNotifier do
  @moduledoc "Emails sent to a user."
  import Swoosh.Email

  alias Dockd.Mailer

  @doc "Sends the sign-in link."
  def deliver_login_instructions(user, url) do
    deliver(user.email, "Entrar no Dockd", """
    Para entrar no Dockd, abra o link abaixo. Ele vale por 15 minutos e uma vez só.

    #{url}

    Se não foi você que pediu, ignore este e-mail.
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:dockd, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
