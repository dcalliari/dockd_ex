defmodule DockdWeb.DockdComponents do
  @moduledoc """
  Function components of the Dockd design system (`design/README.md`).

  Every component emits exactly the `dk-` classes of `design/components/bundle.css`;
  the stylesheet in `assets/css/app.css` is the compiled copy of that system.
  """

  use Phoenix.Component
  use DockdWeb, :verified_routes
  import DockdWeb.CoreComponents, only: [icon: 1, translate_error: 1]

  @statuses Dockd.Library.Shelf.statuses()
  @status_labels %{
    quero: "Quero",
    backlog: "Backlog",
    jogando: "Jogando",
    zerado: "Zerado",
    larguei: "Larguei"
  }
  @months ~w(jan fev mar abr mai jun jul ago set out nov dez)

  @doc "The five statuses, in display order."
  def statuses, do: @statuses

  @doc "Portuguese label of a status."
  def status_label(status), do: Map.fetch!(@status_labels, status)

  # ---------------------------------------------------------------------------
  # Formatting helpers

  @doc "Formats integer cents as Brazilian reais."
  def money(cents, currency \\ "BRL")

  def money(cents, currency) when is_integer(cents) do
    symbol = Map.get(%{"BRL" => "R$", "USD" => "$", "EUR" => "€"}, currency, currency)
    whole = div(abs(cents), 100)
    fraction = rem(abs(cents), 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""
    "#{sign}#{symbol} #{format_integer(whole)},#{fraction}"
  end

  def money(nil, _currency), do: nil

  defp format_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(".", &Enum.join/1)
    |> String.reverse()
  end

  @doc "Parses a reais input (`199,90`, `199.90`, `1.199,90`) into integer cents."
  def parse_money(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:ok, nil}

      Regex.match?(~r/^\d{1,3}(\.\d{3})*,\d{2}$/, value) ->
        parse_digits(value |> String.replace(".", "") |> String.replace(",", "."))

      Regex.match?(~r/^\d+(,\d{1,2})?$/, value) ->
        parse_digits(String.replace(value, ",", "."))

      Regex.match?(~r/^\d+(\.\d{1,2})?$/, value) ->
        parse_digits(value)

      true ->
        :error
    end
  end

  def parse_money(_), do: :error

  defp parse_digits(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, round(number * 100)}
      _ -> :error
    end
  end

  @doc "Formats a date as dd/mm/aaaa."
  def date_pt_br(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")
  def date_pt_br(%DateTime{} = at), do: at |> DateTime.to_date() |> date_pt_br()
  def date_pt_br(nil), do: nil

  @doc "Relative time in Portuguese: hoje, ontem, há 3 dias, há 2 meses, há 1 ano."
  def relative_label(%DateTime{} = at, today \\ Date.utc_today()) do
    days = Date.diff(today, DateTime.to_date(at))

    cond do
      days <= 0 -> "hoje"
      days == 1 -> "ontem"
      days < 30 -> "há #{days} dias"
      days < 365 -> "há #{plural(div(days, 30), "mês", "meses")}"
      true -> "há #{plural(div(days, 365), "ano", "anos")}"
    end
  end

  defp plural(1, singular, _plural), do: "1 #{singular}"
  defp plural(n, _singular, plural), do: "#{n} #{plural}"

  @doc "Portuguese labels for domain enums."
  def enum_label(value) when is_atom(value) and not is_nil(value),
    do: enum_label(Atom.to_string(value))

  def enum_label("nintendo_exclusive"), do: "Exclusivo Nintendo"
  def enum_label("switch2_exclusive"), do: "Exclusivo Switch 2"
  def enum_label("multiplatform"), do: "Multiplataforma"
  def enum_label("switch"), do: "Switch"
  def enum_label("switch_2"), do: "Switch 2"
  def enum_label("physical"), do: "Físico"
  def enum_label("digital"), do: "Digital"
  def enum_label("key_card"), do: "Key card"
  def enum_label("subscription"), do: "Assinatura"
  def enum_label("shared"), do: "Compartilhado"
  def enum_label("borrowed"), do: "Emprestado"
  def enum_label("eshop"), do: "eShop"
  def enum_label(nil), do: nil
  def enum_label(value) when is_binary(value), do: value

  @doc "Platforms of a game's releases, joined by a middle dot."
  def platform_label(releases) do
    releases
    |> Enum.map(& &1.platform)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map_join(" · ", &enum_label/1)
  end

  @doc "Joins metadata parts with a middle dot, dropping blanks."
  def meta(parts), do: parts |> Enum.reject(&(&1 in [nil, "", false])) |> Enum.join(" · ")

  # ---------------------------------------------------------------------------
  # Navigation

  attr :current_scope, :map, required: true, doc: "nil for a visitor"
  attr :current, :string, default: nil, doc: "a destination, or Entrar or Criar conta"
  attr :search, :string, default: ""

  attr :search_live, :boolean,
    default: false,
    doc: "true on Descobrir, where the same field searches as you type"

  def nav_bar(%{current_scope: nil} = assigns) do
    ~H"""
    <header class="dk-nav">
      <.link navigate="/" class="dk-wordmark" aria-label="Dockd, início">dockd<i>.</i></.link>
      <nav class="dk-nav__links" aria-label="Principal">
        <.link
          navigate="/descobrir"
          class="dk-nav__link"
          aria-current={if(@current == "Descobrir", do: "page")}
        >
          Descobrir
        </.link>
      </nav>
      <.nav_search search={@search} search_live={@search_live} />
      <nav class="dk-nav__links dk-nav__guest" aria-label="Conta">
        <.link
          :for={{label, path} <- [{"Entrar", "/entrar"}, {"Criar conta", "/criar-conta"}]}
          navigate={path}
          class="dk-nav__link"
          aria-current={if(label == @current, do: "page")}
        >
          {label}
        </.link>
      </nav>
      <.link
        navigate="/entrar"
        class="dk-nav__link dk-nav__guest-phone"
        aria-current={if(@current == "Entrar", do: "page")}
      >
        Entrar
      </.link>
    </header>
    """
  end

  def nav_bar(assigns) do
    ~H"""
    <header class="dk-nav">
      <.link navigate="/" class="dk-wordmark" aria-label="Dockd, início">dockd<i>.</i></.link>
      <nav class="dk-nav__links" aria-label="Principal">
        <.link
          :for={{label, path} <- destinations()}
          navigate={path}
          class="dk-nav__link"
          aria-current={if(label == @current, do: "page")}
        >
          {label}
        </.link>
      </nav>
      <.nav_search search={@search} search_live={@search_live} />
      <.account_menu user={@current_scope.user} />
    </header>
    """
  end

  attr :search, :string, required: true
  attr :search_live, :boolean, required: true

  defp nav_search(assigns) do
    ~H"""
    <form
      id="nav-search-form"
      class="dk-search dk-nav__search"
      role="search"
      action={if(!@search_live, do: "/descobrir")}
      phx-change={if(@search_live, do: "search")}
      phx-submit={if(@search_live, do: "search")}
    >
      <.icon name="hero-magnifying-glass" />
      <input
        id="nav-search"
        type="search"
        name="q"
        value={@search}
        placeholder="Buscar no catálogo"
        aria-label="Buscar no catálogo"
        autocomplete="off"
        phx-debounce={if(@search_live, do: "300")}
        autofocus={@search_live and @search == ""}
      />
    </form>
    <button
      id="nav-search-toggle"
      type="button"
      class="dk-nav__icon"
      aria-label="Buscar no catálogo"
      phx-hook="NavSearch"
    >
      <.icon name="hero-magnifying-glass" />
    </button>
    """
  end

  @doc """
  The account item of the NavBar: the name opens a menu, like a FilterBar menu, with the
  email, the API token and Sair. Copying the token swaps its label in place.
  """
  attr :user, :map, required: true

  def account_menu(assigns) do
    ~H"""
    <details id="account-menu" class="dk-account">
      <summary>{@user.name} <.icon name="hero-chevron-down" /></summary>
      <ul class="dk-filter__menu">
        <li class="dk-account__who">{@user.email}</li>
        <li>
          <button
            id="account-api-token"
            type="button"
            phx-click="copy_api_token"
            phx-hook=".CopyApiToken"
            phx-update="ignore"
          >
            Copiar token da API
          </button>
        </li>
        <li><.link id="account-sign-out" href={~p"/sair"} method="delete">Sair</.link></li>
      </ul>
    </details>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyApiToken">
      export default {
        mounted() {
          this.handleEvent("copy_api_token", ({token}) => {
            navigator.clipboard.writeText(token).then(() => { this.el.textContent = "Token copiado" })
          })
        }
      }
    </script>
    """
  end

  @doc """
  TextField: the SearchField without the magnifier. No visible label: the placeholder
  says what to type and the `aria-label` repeats it. The error goes under the field.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :placeholder, :string, required: true
  attr :rest, :global, include: ~w(autocomplete disabled readonly required)

  def text_field(assigns) do
    assigns = assign(assigns, :errors, Enum.map(assigns.field.errors, &translate_error/1))

    ~H"""
    <label class={["dk-field", @errors != [] && "is-error"]}>
      <input
        type={@type}
        id={@field.id}
        name={@field.name}
        value={if(@type != "password", do: @field.value)}
        placeholder={@placeholder}
        aria-label={@placeholder}
        aria-invalid={to_string(@errors != [])}
        {@rest}
      />
      <span :for={error <- @errors} class="dk-field__error">{error}</span>
    </label>
    """
  end

  attr :current, :string, default: nil

  def bottom_nav(assigns) do
    ~H"""
    <nav class="dk-bottomnav" aria-label="Principal">
      <.link
        :for={{label, path} <- destinations()}
        navigate={path}
        aria-current={if(label == @current, do: "page")}
      >
        {label}
      </.link>
    </nav>
    """
  end

  defp destinations,
    do: [{"Biblioteca", "/"}, {"Comprar", "/comprar"}, {"Descobrir", "/descobrir"}]

  @doc """
  The one-line footer of every screen but Entrar: small wordmark, Sobre and the IGDB
  credit. Above the bottom navigation on phones, clear of it.
  """
  attr :bottom_nav, :boolean,
    default: false,
    doc: "true when the phone bottom navigation is shown"

  def footer(assigns) do
    ~H"""
    <footer id="site-footer" class={["dk-footer", @bottom_nav && "dk-footer--above-nav"]}>
      <p class="dk-footer__line">
        <.link navigate="/" class="dk-wordmark dk-wordmark--sm" aria-label="Dockd, início">
          dockd<i>.</i>
        </.link>
        <span aria-hidden="true">·</span>
        <.link id="footer-about" navigate={~p"/sobre"}>Sobre</.link>
        <span aria-hidden="true">·</span>
        <span>
          Dados de jogos por
          <a href="https://www.igdb.com" target="_blank" rel="noopener noreferrer">IGDB</a>
        </span>
      </p>
    </footer>
    """
  end

  attr :id, :string, default: nil

  slot :tab, required: true do
    attr :label, :string, required: true
    attr :count, :integer
    attr :selected, :boolean
    attr :patch, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <nav id={@id} class="dk-tabs" aria-label="Status">
      <.link
        :for={tab <- @tab}
        patch={tab.patch}
        class="dk-tab"
        aria-selected={to_string(tab[:selected] == true)}
      >
        {tab.label}
        <span :if={tab[:count]} class="dk-tab__count">{tab.count}</span>
      </.link>
    </nav>
    """
  end

  @doc """
  One dropdown of the FilterBar: an uppercase label that opens a menu of links.

  `options` is a list of `{value, label}` or `{value, label, count}`; the option whose
  value equals `value` is current. `path` builds the patch target for a value.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :options, :list, required: true
  attr :path, :any, required: true, doc: "function from value to a patch path"
  attr :prefix, :string, default: nil, doc: "a lowercase word before the label, like Ordenar por"
  attr :align, :string, default: "start", values: ~w(start end)

  def filter(assigns) do
    current =
      Enum.find(assigns.options, fn option -> elem(option, 0) == assigns.value end)

    assigns = assign(assigns, current: current, active: assigns.value != "" and current != nil)

    ~H"""
    <details
      id={@id}
      class={["dk-filter", @active && "dk-filter--active", @align == "end" && "dk-filter--end"]}
    >
      <summary>
        <small :if={@prefix}>{@prefix}</small>
        <b :if={@active}>{elem(@current, 1)}</b>
        <span :if={!@active}>{@label}</span>
        <.icon name="hero-chevron-down" />
      </summary>
      <ul class="dk-filter__menu">
        <li :for={option <- @options}>
          <.link
            patch={@path.(elem(option, 0))}
            aria-current={to_string(elem(option, 0) == @value)}
            phx-click={Phoenix.LiveView.JS.remove_attribute("open", to: "##{@id}")}
          >
            {elem(option, 1)}
            <small :if={tuple_size(option) == 3}>{elem(option, 2)}</small>
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  attr :title, :string, required: true
  attr :count, :integer, default: nil
  attr :id, :string, default: nil
  slot :action

  def section_head(assigns) do
    ~H"""
    <div id={@id} class="dk-section">
      <h2>{@title}<span :if={@count}>{@count}</span></h2>
      {render_slot(@action)}
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Content

  attr :title, :string, required: true
  attr :cover_url, :string, default: nil
  attr :status, :atom, default: nil
  attr :navigate, :string, default: nil
  attr :size, :string, default: "grid", values: ~w(grid sm)
  attr :faded, :boolean, default: false
  attr :rest, :global
  slot :inner_block

  def poster(assigns) do
    assigns =
      assign(assigns, :class, [
        "dk-poster",
        assigns.size == "sm" && "dk-poster--sm",
        is_nil(assigns.cover_url) && "dk-poster--empty",
        assigns.faded && "dk-poster--faded"
      ])

    ~H"""
    <.link :if={@navigate} navigate={@navigate} class={@class} aria-label={@title} {@rest}>
      <.poster_body title={@title} cover_url={@cover_url} status={@status} size={@size} />
      {render_slot(@inner_block)}
    </.link>
    <span :if={!@navigate} class={@class} {@rest}>
      <.poster_body title={@title} cover_url={@cover_url} status={@status} size={@size} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp poster_body(assigns) do
    ~H"""
    <img :if={@cover_url} src={@cover_url} alt="" loading="lazy" />
    <span :if={is_nil(@cover_url) and @size == "grid"}>{@title}</span>
    <.status_chip
      :if={@status && @size == "grid"}
      status={@status}
      size="sm"
      class="dk-poster__status"
    />
    """
  end

  attr :platforms, :string, required: true
  attr :exclusive, :boolean, default: false

  def poster_caption(assigns) do
    ~H"""
    <p class="dk-poster-caption">
      <span>{@platforms}</span>
      <span :if={@exclusive} class="dk-poster-caption__mark">Exclusivo</span>
    </p>
    """
  end

  attr :status, :atom, required: true, values: @statuses
  attr :size, :string, default: "md", values: ~w(md sm)
  attr :class, :any, default: nil
  attr :rest, :global

  def status_chip(assigns) do
    ~H"""
    <span
      class={["dk-status", "dk-status--#{@status}", @size == "sm" && "dk-status--sm", @class]}
      {@rest}
    >
      {status_label(@status)}
    </span>
    """
  end

  @doc """
  The status control, the same on every screen that shows a game's status.

  The current StatusChip is the trigger: pointing at it opens the other statuses below it,
  and clicking it clears the status, which takes the game out of the library. On a touch
  screen the first tap opens and the second clears (hook `StatusMenu`). `status` nil renders
  the add chip. `options` are the statuses offered (`Dockd.Library.status_options/1`); every
  button sends its event with the `values` pairs. `ask` swaps the options for the versions
  the game can be owned in, after Backlog on a game without ownership.
  """
  attr :id, :string, required: true
  attr :status, :atom, default: nil
  attr :options, :list, required: true
  attr :values, :map, default: %{}
  attr :size, :string, default: "sm", values: ~w(md sm)
  attr :since, :any, default: nil, doc: "when the status was set, shown on the game page"
  attr :open, :boolean, default: false, doc: "opened by the URL (`abrir`)"
  attr :ask, :list, default: nil, doc: "`%{label, release_id, media}` choices to own"

  def status_menu(assigns) do
    assigns =
      assign(assigns,
        phx_values: Map.new(assigns.values, fn {k, v} -> {"phx-value-#{k}", v} end),
        shown: assigns.open or assigns.ask != nil
      )

    ~H"""
    <div
      id={@id}
      class={["dk-status-menu", @shown && "is-open"]}
      phx-hook="StatusMenu"
      data-open={to_string(@shown)}
    >
      <button
        :if={@status}
        type="button"
        class="dk-status-menu__current"
        aria-haspopup="true"
        aria-expanded={to_string(@shown)}
        aria-label={"#{status_label(@status)}: tirar da biblioteca"}
        title="Tirar da biblioteca"
        phx-click="set_status"
        phx-value-status=""
        {@phx_values}
      >
        <.status_chip status={@status} size={@size} />
      </button>
      <button
        :if={!@status}
        type="button"
        class="dk-status-menu__current"
        aria-haspopup="true"
        aria-expanded={to_string(@shown)}
      >
        <span class={["dk-status", "dk-status--add", @size == "sm" && "dk-status--sm"]}>
          + Adicionar
        </span>
      </button>
      <span :if={@since} class="dk-status-menu__since">desde {date_pt_br(@since)}</span>
      <div :if={!@ask} class="dk-status-menu__options" role="group" aria-label="Mudar status">
        <button
          :for={option <- @options}
          type="button"
          class={["dk-status", "dk-status--#{option}"]}
          phx-click="set_status"
          phx-value-status={option}
          {@phx_values}
        >
          {status_label(option)}
        </button>
      </div>
      <div :if={@ask} class="dk-status-menu__options dk-status-menu__ask" role="group">
        <span>Tem em qual versão?</span>
        <button
          :for={choice <- @ask}
          type="button"
          phx-click="own"
          phx-value-release_id={choice.release_id}
          phx-value-media={choice.media}
          {@phx_values}
        >
          {choice.label}
        </button>
        <button type="button" class="dk-link" phx-click="close_status">Cancelar</button>
      </div>
    </div>
    """
  end

  @doc """
  The add chip for a visitor, in the place of `status_menu/1`: a link to Entrar that comes
  back to `back`, where the same control opens. Nothing is saved until the account picks a
  status.
  """
  attr :back, :string, required: true
  attr :id, :string, default: nil
  attr :size, :string, default: "sm", values: ~w(md sm)

  def status_link(assigns) do
    ~H"""
    <.link
      id={@id}
      href={DockdWeb.UserAuth.sign_in_path(@back)}
      class="dk-status-menu"
      title="Entrar para adicionar"
    >
      <span class={["dk-status", "dk-status--add", @size == "sm" && "dk-status--sm"]}>
        + Adicionar
      </span>
    </.link>
    """
  end

  @doc "A release by platform, and its edition when it is not the standard one."
  def release_label(release) do
    if release.edition in [nil, "", "Edição padrão"],
      do: enum_label(release.platform),
      else: "#{enum_label(release.platform)} · #{release.edition}"
  end

  @doc """
  Comprei, the same in Comprar and on the game page (Comprei · A, `maquetes/compra.html`).
  Before: the button. With more than one version or media: the choices, each one the
  purchase. After, while the screen is open: what was paid, which opens its own value, and
  Desfazer. The row shows the new Backlog tag; the game page already has it in its menu.
  """
  attr :id, :string, required: true
  attr :game_id, :string, required: true
  attr :choices, :list, default: nil, doc: "from `GameEvents.buying/2`"
  attr :purchase, :map, default: nil, doc: "the purchase made on this screen"
  attr :form, :map, default: nil
  attr :error, :string, default: nil
  attr :place, :string, default: "row", values: ~w(row hero)

  def buy_control(assigns) do
    assigns =
      assign(
        assigns,
        :editing,
        assigns.form && assigns.form.kind == :paid && assigns.form.key == assigns.game_id
      )

    ~H"""
    <div id={@id} class="dk-buy">
      <%= cond do %>
        <% @purchase -> %>
          <.status_chip :if={@place == "row"} status={:backlog} />
          <form :if={@editing} class="dk-buy__paid" phx-submit="save_paid">
            <input type="hidden" name="game_id" value={@game_id} />
            <label class={["dk-form__field", @error && "is-error"]}>
              <span class="dk-money">
                <input
                  name="price"
                  inputmode="decimal"
                  placeholder="199,90"
                  aria-label="Valor pago"
                  value={money_input(@purchase.price_cents)}
                  autofocus
                />
              </span>
              <span :if={@error} class="dk-field__error">{@error}</span>
            </label>
            <.btn type="submit" size="sm" variant="primary">Registrar valor</.btn>
            <button type="button" class="dk-link" phx-click="cancel">Cancelar</button>
          </form>
          <.paid :if={!@editing} purchase={@purchase} game_id={@game_id} />
          <button
            :if={!@editing}
            type="button"
            class="dk-link"
            phx-click="undo_purchase"
            phx-value-game_id={@game_id}
          >
            Desfazer
          </button>
        <% @choices -> %>
          <div class="dk-choice" role="group" aria-label="Comprou qual">
            <button
              :for={choice <- @choices}
              type="button"
              phx-click="buy"
              phx-value-game_id={@game_id}
              phx-value-release_id={choice.release_id}
              phx-value-media={choice.media}
            >
              {choice.label}
            </button>
          </div>
          <button type="button" class="dk-link" phx-click="cancel">Cancelar</button>
        <% true -> %>
          <.btn
            id={"#{@id}-button"}
            variant={if(@place == "hero", do: "primary", else: "secondary")}
            size={if(@place == "hero", do: "md", else: "sm")}
            phx-click="buy"
            phx-value-game_id={@game_id}
          >
            Comprei
          </.btn>
      <% end %>
    </div>
    """
  end

  attr :purchase, :map, required: true
  attr :game_id, :string, required: true

  defp paid(assigns) do
    ~H"""
    <button
      type="button"
      class={["dk-price", "dk-price--paid", !@purchase.price_cents && "dk-price--none"]}
      phx-click="paid_form"
      phx-value-game_id={@game_id}
    >
      <%= if @purchase.price_cents do %>
        <b>{money(@purchase.price_cents, @purchase.currency)}</b>
        <small>
          pago em {date_pt_br(@purchase.purchased_at)}{if @purchase.retailer,
            do: " · #{@purchase.retailer}"}
        </small>
      <% else %>
        <b>Sem valor</b>
      <% end %>
    </button>
    """
  end

  defp money_input(nil), do: ""
  defp money_input(cents), do: cents |> money() |> String.replace("R$ ", "")

  @doc """
  The manual price record, opened by clicking a price in Comprar or on the game page: the
  version and media when there is a choice, the price seen and where, and the prices
  already seen for the same game underneath.
  """
  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :error, :string, default: nil

  def price_form(assigns) do
    media =
      assigns.form.releases |> Enum.flat_map(&Dockd.Catalog.Release.media/1) |> Enum.uniq()

    assigns =
      assign(assigns,
        release_options: Enum.map(assigns.form.releases, &{&1.id, release_label(&1)}),
        media_options: Enum.map(media, &{Atom.to_string(&1), enum_label(&1)})
      )

    ~H"""
    <form id={@id} class="dk-form" phx-submit="save_price">
      <.choice_field name="release_id" label="Versão" options={@release_options} />
      <.choice_field name="format" label="Mídia" options={@media_options} />
      <label class={["dk-form__field", @error && "is-error"]}>
        <span>Preço visto</span>
        <span class="dk-money">
          <input
            name="price"
            inputmode="decimal"
            placeholder="199,90"
            aria-label="Preço visto"
            autofocus
          />
        </span>
        <span :if={@error} class="dk-field__error">{@error}</span>
      </label>
      <label class="dk-form__field">
        <span>Onde</span>
        <input name="source" value="eShop" aria-label="Onde viu" />
      </label>
      <div class="dk-form__actions">
        <.btn type="submit" size="sm" variant="primary">Registrar preço</.btn>
        <button type="button" class="dk-link" phx-click="cancel">Cancelar</button>
      </div>
      <ul :if={@form.seen != []} class="dk-seen" aria-label="Preços vistos">
        <li :for={seen <- @form.seen}>
          <b>{money(seen.price_cents, seen.currency)}</b>
          <span>{meta([seen.source, enum_label(seen.format), @form.names[seen.release_id]])}</span>
          <time>{date_pt_br(seen.observed_at)}</time>
        </li>
      </ul>
    </form>
    """
  end

  @doc """
  A choice among the few options that exist, as radio buttons under a `t-label`. The first
  option is selected; a single option is not a choice and shows as text.
  """
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true, doc: "`{value, label}` pairs"

  def choice_field(assigns) do
    ~H"""
    <div class="dk-form__field">
      <span>{@label}</span>
      <%= case @options do %>
        <% [{value, text}] -> %>
          <input type="hidden" name={@name} value={value} />
          <span class="dk-media">{text}</span>
        <% options -> %>
          <div class="dk-choice" role="radiogroup" aria-label={@label}>
            <label :for={{{value, text}, index} <- Enum.with_index(options)}>
              <input type="radio" name={@name} value={value} checked={index == 0} />
              <span>{text}</span>
            </label>
          </div>
      <% end %>
    </div>
    """
  end

  attr :media, :atom, required: true

  def media_tag(assigns) do
    ~H"""
    <span class="dk-media">{enum_label(@media)}</span>
    """
  end

  attr :variant, :string, default: "secondary", values: ~w(primary secondary)
  attr :size, :string, default: "md", values: ~w(md sm)
  attr :type, :string, default: "button"
  attr :class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(disabled form name value phx-click phx-value-id phx-value-status phx-value-game_id)

  slot :inner_block, required: true

  def btn(assigns) do
    ~H"""
    <button
      type={@type}
      class={["dk-btn", "dk-btn--#{@variant}", @size == "sm" && "dk-btn--sm", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :date, Date, default: nil
  attr :precision, :atom, default: :day
  attr :today, Date, default: nil

  def date_block(assigns) do
    today = assigns.today || Date.utc_today()
    soon = assigns.date && Date.diff(assigns.date, today) in 0..14
    assigns = assign(assigns, soon: soon, month: assigns.date && month_label(assigns.date))

    ~H"""
    <span
      :if={@precision == :day}
      class={["dk-date", @soon && "dk-date--soon"]}
      title={date_pt_br(@date)}
    >
      <b>{String.pad_leading(Integer.to_string(@date.day), 2, "0")}</b><small>{@month}</small>
    </span>
    <span :if={@precision in [:month, :quarter]} class="dk-date dk-date--month">
      <b>{@month}</b><small>{@date.year}</small>
    </span>
    <span :if={@precision == :year} class="dk-date dk-date--year"><b>{@date.year}</b></span>
    """
  end

  @doc "Three-letter Portuguese month of a date."
  def month_label(%Date{month: month}), do: Enum.at(@months, month - 1)

  @doc """
  A seen price with its date, or `Sem preço`. With `game_id` it is the control that opens
  the manual price record (`price_form/1`), like the status tag opens the status menu;
  `release_id` narrows it to one version.
  """
  attr :observation, :map, default: nil, doc: "a price observation, or nil"
  attr :now, DateTime, default: nil
  attr :id, :string, default: nil
  attr :game_id, :string, default: nil
  attr :release_id, :string, default: nil
  attr :open, :boolean, default: false

  def price(assigns) do
    now = assigns.now || DateTime.utc_now()

    stale =
      assigns.observation && Dockd.Purchasing.stale?(assigns.observation, now, 30)

    assigns = assign(assigns, :stale, stale)

    ~H"""
    <button
      :if={@game_id}
      id={@id}
      type="button"
      class={["dk-price", @stale && "dk-price--stale", !@observation && "dk-price--none"]}
      aria-expanded={to_string(@open)}
      phx-click="price_form"
      phx-value-game_id={@game_id}
      phx-value-release_id={@release_id}
    >
      <.price_text observation={@observation} stale={@stale} />
    </button>
    <span
      :if={!@game_id and @observation}
      id={@id}
      class={["dk-price", @stale && "dk-price--stale"]}
    >
      <.price_text observation={@observation} stale={@stale} />
    </span>
    """
  end

  attr :observation, :map, default: nil
  attr :stale, :boolean, default: false

  defp price_text(%{observation: nil} = assigns), do: ~H"<b>Sem preço</b>"

  defp price_text(assigns) do
    ~H"""
    <b>{money(@observation.price_cents, @observation.currency)}</b>
    <small>
      visto em {date_pt_br(@observation.observed_at)}{if @observation.source,
        do: " · #{@observation.source}"}{if @stale, do: " · desatualizado"}
    </small>
    """
  end

  attr :id, :string, default: nil
  slot :inner_block, required: true

  def empty_state(assigns) do
    ~H"""
    <p id={@id} class="dk-empty">{render_slot(@inner_block)}</p>
    """
  end

  attr :items, :list, required: true, doc: "maps with :what, :at (DateTime), :who, :current"
  attr :id, :string, default: nil

  def history(assigns) do
    ~H"""
    <ol id={@id} class="dk-history">
      <li
        :for={item <- @items}
        class={["dk-history__item", item[:current] && "dk-history__item--current"]}
      >
        <div class="dk-history__what">
          {item.what} <small>{relative_label(item.at)}</small>
        </div>
        <div class="dk-history__who">{meta([date_pt_br(item.at) | List.wrap(item[:who])])}</div>
      </li>
    </ol>
    """
  end
end
