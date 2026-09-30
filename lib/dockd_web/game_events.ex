defmodule DockdWeb.GameEvents do
  @moduledoc """
  The events a game answers to on every screen, handled once so the status control,
  Comprei and the price do the same thing wherever they appear (design/README.md, Uma
  ação, um efeito).

  A LiveView delegates `events/0` here and passes the function that reloads what it shows:

      def handle_event(event, params, socket) when event in @game_events,
        do: GameEvents.handle_event(event, params, socket, &load/1)

  The screen keeps these assigns, set by `init/2`: `status_open`, a menu the URL asked to
  open (`abrir`); `asking`, the game whose Backlog waits for the version it is owned in;
  `buying`, the game whose Comprei waits for a version, edition or media; `bought`, the purchases
  made on this screen, which show Desfazer until the screen is left; and `form`, the price
  or paid value being typed, with its `form_error`.
  """
  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import DockdWeb.DockdComponents, only: [parse_money: 1, release_label: 1, enum_label: 1]

  alias Dockd.{Catalog, Library, Purchasing}
  alias Dockd.Catalog.Release
  alias Dockd.Library.Shelf

  @events ~w(set_status own own_elsewhere close_status buy more_choices undo_purchase paid_form save_paid price_form save_price cancel)
  @media %{"physical" => :physical, "digital" => :digital}

  @doc "Event names handled here."
  def events, do: @events

  @doc "Closes every menu and form, or opens the status menu the URL named."
  def init(socket, open \\ nil) do
    socket
    |> assign(:status_open, open)
    |> assign(:asking, nil)
    |> assign(:buying, nil)
    |> assign(:form, nil)
    |> assign(:form_error, nil)
    |> assign_new(:bought, fn -> %{} end)
  end

  @doc """
  The versions to own for the card of `item` (a shelf item or a Descobrir result), when
  its game is the one asking; nil otherwise.
  """
  def ask(nil, _item), do: nil

  def ask(asking, %{game: game}), do: if(game.id == asking.game.id, do: asking.choices)

  @doc """
  The version and media choices Comprei offers in place for `game_id`, when it is asking
  and no edition is on sale.
  """
  def buying(%{game_id: game_id, choices: choices, options: false}, game_id), do: choices
  def buying(_buying, _game_id), do: nil

  @doc """
  The options Comprei opens under the row for `game_id` when an edition is on sale
  (`maquetes/edicoes.html`, caminho B): `%{choices:, all:}`, each choice with its price.
  """
  def buy_options(%{game_id: game_id, options: true} = buying, game_id),
    do: Map.take(buying, [:choices, :all])

  def buy_options(_buying, _game_id), do: nil

  @doc """
  What Comprei can buy for a game: one choice per platform's standard release and media
  it is sold in, always including the media Comprar's MediaTag already has the account
  on (the release's physical_available/digital_available only says what the catalog has
  seen sold, never a reason to keep the account from registering the other one), then
  the store editions on sale, cheapest first, each with the price the purchase records.
  The label names only what differs between the standard choices; `name` and `meta`
  describe any choice in the options under the row.
  """
  def purchase_choices(user, %{id: game_id, releases: releases}) do
    preferred = user |> Library.get_entry_for_game(game_id) |> Library.media()
    standard = standard_choices(releases, preferred)

    editions =
      releases
      |> Enum.reject(&Release.standard?/1)
      |> Enum.flat_map(fn release ->
        case Purchasing.current_price(user, release.id, :digital) do
          %{sales_status: "sales_termination"} ->
            []

          nil ->
            []

          price ->
            [
              %{
                release: release,
                media: :digital,
                label: release_label(release),
                edition: true,
                price: price
              }
            ]
        end
      end)

    standard =
      Enum.map(standard, fn choice ->
        Map.merge(choice, %{
          edition: false,
          price: Purchasing.current_price(user, choice.release.id, choice.media)
        })
      end)

    standard ++ Enum.sort_by(editions, & &1.price.price_cents)
  end

  # The account's chosen media (Comprar's MediaTag) always joins whatever the release
  # itself is known to sell in, so Comprei can never foreclose the media the account
  # says it wants, whatever the catalog does or does not know about the release.
  defp standard_choices(releases, preferred) do
    pairs =
      for r <- standard_releases(releases),
          m <- Enum.uniq([preferred | Release.media(r)]),
          do: {r, m}

    many_releases? = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() > 1
    many_media? = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() > 1

    Enum.map(pairs, fn {release, media} ->
      label =
        cond do
          many_releases? and many_media? -> "#{release_label(release)} · #{enum_label(media)}"
          many_releases? -> release_label(release)
          true -> enum_label(media)
        end

      %{release: release, media: media, label: label}
    end)
  end

  def handle_event("set_status", %{"status" => status} = params, socket, reload) do
    with {:ok, status} <- parse_status(status),
         {:ok, game} <- resolve_game(params) do
      case Library.set_status(user(socket), game, status) do
        {:ok, _} ->
          {:noreply, socket |> init() |> reload.()}

        {:error, :needs_ownership} ->
          {:noreply, socket |> ask_ownership(game, status) |> reload.()}

        {:error, _} ->
          {:noreply, failed(socket)}
      end
    else
      _ -> {:noreply, failed(socket)}
    end
  end

  def handle_event(
        "own",
        %{"release_id" => release_id, "media" => media} = params,
        socket,
        reload
      ) do
    status = asking_status(socket)

    with {:ok, game} <- resolve_game(params),
         {:ok, _} <-
           Library.set_status(user(socket), game, status,
             ownership: %{
               release_id: release_id,
               ownership_type: Map.get(@media, media, :digital)
             }
           ) do
      {:noreply, socket |> init() |> reload.()}
    else
      _ -> {:noreply, failed(socket)}
    end
  end

  # The "Joguei em outro lugar" escape in the ask panel: for a played status only, since
  # Backlog means owning but never having started, so there is nowhere else to have played.
  def handle_event("own_elsewhere", params, socket, reload) do
    status = asking_status(socket)

    with {:ok, game} <- resolve_game(params),
         true <- status in [:jogando, :pausado, :zerado, :larguei],
         {:ok, _} <- Library.set_status(user(socket), game, status, owned_elsewhere: true) do
      {:noreply, socket |> init() |> reload.()}
    else
      _ -> {:noreply, failed(socket)}
    end
  end

  def handle_event("close_status", _params, socket, _reload), do: {:noreply, init(socket)}

  # Comprei in one tap: with a single version and media it buys at once; otherwise the
  # control asks which one, and the answer is the purchase. With an edition on sale the
  # choices open under the row with their prices, since the price decides.
  def handle_event("buy", %{"game_id" => game_id} = params, socket, reload) do
    game = Catalog.get_game!(game_id)
    choices = purchase_choices(user(socket), game)

    case pick(choices, params) do
      {:ok, choice} ->
        buy(socket, game, choice, reload)

      :ask ->
        buying = %{
          game_id: game.id,
          options: Enum.any?(choices, & &1.edition),
          all: false,
          choices: Enum.map(choices, &choice_view/1)
        }

        {:noreply, socket |> init() |> assign(:buying, buying)}
    end
  end

  def handle_event("more_choices", _params, socket, _reload),
    do: {:noreply, update_buying(socket, &%{&1 | all: true})}

  def handle_event("undo_purchase", %{"game_id" => game_id}, socket, reload) do
    with {:ok, purchase} <- Map.fetch(socket.assigns.bought, game_id),
         {:ok, _} <- Purchasing.undo_purchase(user(socket), purchase) do
      {:noreply,
       socket
       |> init()
       |> assign(:bought, Map.delete(socket.assigns.bought, game_id))
       |> reload.()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("paid_form", %{"game_id" => game_id}, socket, _reload),
    do: {:noreply, socket |> init() |> assign(:form, %{kind: :paid, key: game_id})}

  def handle_event("save_paid", %{"game_id" => game_id, "price" => price}, socket, reload) do
    with {:ok, purchase} <- Map.fetch(socket.assigns.bought, game_id),
         {:ok, cents} <- parse_money(price),
         {:ok, purchase} <-
           Purchasing.update_purchase(user(socket), purchase, %{price_cents: cents}) do
      bought = Map.put(socket.assigns.bought, game_id, purchase)
      {:noreply, socket |> init() |> assign(:bought, bought) |> reload.()}
    else
      _ -> {:noreply, assign(socket, :form_error, "Use 199,90")}
    end
  end

  def handle_event("price_form", %{"game_id" => game_id} = params, socket, _reload) do
    game = Catalog.get_game!(game_id)

    releases =
      case params["release_id"] do
        nil -> standard_releases(game.releases)
        release_id -> Enum.filter(game.releases, &(&1.id == release_id))
      end

    seen =
      releases
      |> Enum.flat_map(&Purchasing.list_price_observations(user(socket), &1.id))
      |> Enum.sort_by(& &1.observed_at, {:desc, DateTime})
      |> Enum.take(5)

    form = %{
      kind: :price,
      key: params["release_id"] || game_id,
      releases: releases,
      seen: seen,
      names: Map.new(game.releases, &{&1.id, release_label(&1)})
    }

    {:noreply, socket |> init() |> assign(:form, form)}
  end

  def handle_event("save_price", %{"release_id" => release_id} = params, socket, reload) do
    with {:ok, cents} when is_integer(cents) <- parse_money(params["price"]),
         {:ok, _} <-
           Purchasing.create_price_observation(user(socket), %{
             release_id: release_id,
             format: Map.get(@media, params["format"], :digital),
             price_cents: cents,
             observed_at: DateTime.utc_now(),
             source: blank_to(params["source"], "eShop")
           }) do
      {:noreply, socket |> init() |> reload.()}
    else
      {:ok, nil} -> {:noreply, assign(socket, :form_error, "Informe o preço visto")}
      _ -> {:noreply, assign(socket, :form_error, "Use 199,90")}
    end
  end

  def handle_event("cancel", _params, socket, _reload), do: {:noreply, init(socket)}

  defp user(socket), do: socket.assigns.current_scope.user

  defp update_buying(%{assigns: %{buying: nil}} = socket, _fun), do: socket
  defp update_buying(socket, fun), do: assign(socket, :buying, fun.(socket.assigns.buying))

  defp choice_view(choice) do
    %{
      release_id: choice.release.id,
      media: choice.media,
      label: choice.label,
      edition: choice.edition,
      name: if(choice.edition, do: choice.release.edition, else: "Edição padrão"),
      meta: "#{enum_label(choice.release.platform)} · #{enum_label(choice.media)}",
      price: choice.price
    }
  end

  defp pick([only], _params), do: {:ok, only}

  defp pick(choices, %{"release_id" => release_id, "media" => media}) do
    case Enum.find(choices, &(&1.release.id == release_id and Atom.to_string(&1.media) == media)) do
      nil -> :ask
      choice -> {:ok, choice}
    end
  end

  defp pick(_choices, _params), do: :ask

  # The purchase takes the price shown for that version and media, when there is one.
  defp buy(socket, game, %{release: release, media: media}, reload) do
    price = Purchasing.current_price(user(socket), release.id, media)

    attrs = %{
      release_id: release.id,
      format: media,
      purchased_at: DateTime.utc_now(),
      price_cents: price && price.price_cents,
      currency: price && price.currency,
      retailer: price && price.source
    }

    case Purchasing.create_purchase(user(socket), attrs) do
      {:ok, purchase} ->
        bought = Map.put(socket.assigns.bought, game.id, purchase)
        {:noreply, socket |> init() |> assign(:bought, bought) |> reload.()}

      {:error, _} ->
        {:noreply, socket |> init() |> put_flash(:error, "Não foi possível registrar.")}
    end
  end

  # An empty status is the current tag clicked again: out of the library.
  defp parse_status(""), do: {:ok, nil}

  defp parse_status(status) do
    case Enum.find(Shelf.statuses(), &(Atom.to_string(&1) == status)) do
      nil -> :error
      status -> {:ok, status}
    end
  end

  defp resolve_game(%{"game_id" => game_id}), do: {:ok, Catalog.get_game!(game_id)}
  defp resolve_game(_params), do: :error

  defp standard_releases(releases),
    do: releases |> Enum.filter(&Release.standard?/1) |> Enum.sort_by(& &1.platform)

  defp asking_status(%{assigns: %{asking: %{status: status}}}), do: status
  defp asking_status(_socket), do: :backlog

  # Platform and media only: the exact edition comes with a purchase. Jogando, Pausado,
  # Zerado and Larguei also offer "Joguei em outro lugar" (owned_elsewhere); Backlog does
  # not, since it means owning but never having started.
  defp ask_ownership(socket, game, status) do
    game = Catalog.get_game!(game.id)

    versions =
      for release <- standard_releases(game.releases),
          media <- [:physical, :digital],
          do: %{
            release_id: release.id,
            media: media,
            label: "#{release_label(release)} · #{enum_label(media)}"
          }

    elsewhere =
      if status in [:jogando, :pausado, :zerado, :larguei],
        do: [%{elsewhere: true, label: "Joguei em outro lugar"}],
        else: []

    socket
    |> assign(:status_open, nil)
    |> assign(:asking, %{game: game, status: status, choices: versions ++ elsewhere})
  end

  defp failed(socket),
    do: socket |> init() |> put_flash(:error, "Não foi possível mudar o status.")

  defp blank_to(value, default) when value in [nil, ""], do: default
  defp blank_to(value, _default), do: value
end
