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
    pausado: "Pausado",
    zerado: "Zerado",
    larguei: "Larguei"
  }
  @months ~w(jan fev mar abr mai jun jul ago set out nov dez)

  @doc "The six statuses, in display order."
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
  attr :catalog_review, :integer, default: 0, doc: "questions waiting in Conferir catálogo"
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
      <.account_menu user={@current_scope.user} catalog_review={@catalog_review} />
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
  email, the public profile, Conferir catálogo while something waits for a person, the API token and Sair.
  Copying the token swaps its label in place.
  """
  attr :user, :map, required: true
  attr :catalog_review, :integer, default: 0

  def account_menu(assigns) do
    ~H"""
    <details id="account-menu" class="dk-account">
      <summary>{@user.name} <.icon name="hero-chevron-down" /></summary>
      <ul class="dk-filter__menu">
        <li class="dk-account__who">{@user.email}</li>
        <li :if={@user.username}>
          <.link id="account-profile" navigate={~p"/u/#{@user.username}"}>Perfil</.link>
        </li>
        <li><.link id="account-settings" navigate={~p"/configuracoes"}>Configurações</.link></li>
        <li :if={@user.admin and @catalog_review > 0}>
          <.link id="account-catalog-review" navigate={~p"/conferir"}>
            Conferir catálogo <small>{@catalog_review}</small>
          </.link>
        </li>
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
  attr :rest, :global, include: ~w(autocomplete disabled readonly required maxlength phx-debounce)

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
    do: [
      {"Início", "/"},
      {"Biblioteca", "/biblioteca"},
      {"Comprar", "/comprar"},
      {"Descobrir", "/descobrir"}
    ]

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
  attr :availability, :atom, default: nil
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
      <.poster_body
        title={@title}
        cover_url={@cover_url}
        status={@status}
        size={@size}
        availability={@availability}
      />
      {render_slot(@inner_block)}
    </.link>
    <span :if={!@navigate} class={@class} {@rest}>
      <.poster_body
        title={@title}
        cover_url={@cover_url}
        status={@status}
        size={@size}
        availability={@availability}
      />
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
    <.exclusive_mark :if={@size == "grid"} availability={@availability} />
    """
  end

  attr :platforms, :string, required: true

  def poster_caption(assigns) do
    ~H"""
    <p class="dk-poster-caption">
      <span>{@platforms}</span>
    </p>
    """
  end

  @doc """
  The exclusivity mark: the console's own game card, black for a Nintendo
  exclusive and red for a Switch 2 exclusive. A multiplatform game has none.
  """
  attr :availability, :atom, default: nil

  def exclusive_mark(assigns) do
    ~H"""
    <svg
      :if={@availability in [:nintendo_exclusive, :switch2_exclusive]}
      class={["dk-exclusive", "dk-exclusive--#{exclusive_kind(@availability)}"]}
      viewBox="0 0 16 22"
      role="img"
      aria-label={enum_label(@availability)}
    >
      <title>{enum_label(@availability)}</title>
      <path d="M4.5 .5H14A1.5 1.5 0 0 1 15.5 2V20A1.5 1.5 0 0 1 14 21.5H2A1.5 1.5 0 0 1 .5 20V4.5Z" />
    </svg>
    """
  end

  defp exclusive_kind(:nintendo_exclusive), do: "nintendo"
  defp exclusive_kind(:switch2_exclusive), do: "switch2"

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
  the game can be owned in, after Backlog, Jogando, Pausado, Zerado or Larguei on a game
  without ownership; a played status also offers "Joguei em outro lugar"
  (`%{elsewhere: true, label:}`, sent as `own_elsewhere` instead of `own`).
  """
  attr :id, :string, required: true
  attr :status, :atom, default: nil
  attr :options, :list, required: true
  attr :values, :map, default: %{}
  attr :size, :string, default: "sm", values: ~w(md sm)
  attr :since, :any, default: nil, doc: "when the status was set, shown on the game page"
  attr :open, :boolean, default: false, doc: "opened by the URL (`abrir`)"

  attr :ask, :list,
    default: nil,
    doc: "`%{label, release_id, media}` choices to own, or `%{label, elsewhere: true}`"

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
          phx-click={if Map.get(choice, :elsewhere), do: "own_elsewhere", else: "own"}
          phx-value-release_id={choice[:release_id]}
          phx-value-media={choice[:media]}
          class={Map.get(choice, :elsewhere) && "dk-link--muted"}
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
    if Dockd.Catalog.Release.standard?(release),
      do: enum_label(release.platform),
      else: "#{enum_label(release.platform)} · #{release.edition}"
  end

  @doc """
  An edition's short name, without the word edition: "Digital Deluxe" for "Edição
  Digital Deluxe"; nil for the standard edition.
  """
  def edition_label(release) do
    if Dockd.Catalog.Release.standard?(release) do
      nil
    else
      case Regex.replace(~r/\b(?:edição|edicao|edition)\b/iu, release.edition, "")
           |> String.replace(~r/\s+/u, " ")
           |> String.trim() do
        "" -> release.edition
        short -> short
      end
    end
  end

  @doc """
  MatchRow (`maquetes/casar-eshop.html`, caminho A): a version whose eShop product the
  sync could not settle, with up to three candidates. `É este` confirms one and the row
  shows its price; `Não está na eShop` records that the store does not sell it; both
  change the row in place, and `Desfazer` brings the candidates back. No dialog.
  """
  attr :id, :string, required: true
  attr :listing, Dockd.Pricing.StoreListing, required: true, doc: "with release and game"
  attr :price, :map, default: nil, doc: "the store price once confirmed"
  attr :error, :string, default: nil

  def eshop_match(assigns) do
    ~H"""
    <div id={@id} class="dk-match" data-state={@listing.match}>
      <div class="dk-row">
        <.poster
          title={@listing.release.game.title}
          cover_url={@listing.release.game.cover_url}
          size="sm"
          navigate={~p"/jogos/#{@listing.release.game.id}"}
        />
        <div>
          <.link navigate={~p"/jogos/#{@listing.release.game.id}"} class="dk-row__title">
            {@listing.release.game.title}
          </.link>
          <div class="dk-row__meta">
            {meta([enum_label(@listing.release.platform), match_state(@listing)])}
          </div>
        </div>
        <div class="dk-row__end">
          <.price :if={@listing.match == :confirmed} observation={@price} />
          <button
            :if={@listing.match in [:confirmed, :rejected]}
            id={"#{@id}-undo"}
            type="button"
            class="dk-link"
            phx-click="undo"
            phx-value-id={@listing.id}
          >
            Desfazer
          </button>
        </div>
      </div>
      <ul :if={@listing.match == :review} class="dk-match__options">
        <li
          :for={candidate <- @listing.candidates}
          id={"#{@id}-#{candidate["external_id"]}"}
          class="dk-match__option"
        >
          <div>
            <a
              :if={candidate["url"]}
              href={"https://www.nintendo.com" <> candidate["url"]}
              target="_blank"
              rel="noopener noreferrer"
              class="dk-row__title"
            >
              {candidate["title"]}
            </a>
            <span :if={!candidate["url"]} class="dk-row__title">{candidate["title"]}</span>
            <div class="dk-row__meta">{candidate_meta(candidate)}</div>
          </div>
          <div class="dk-row__end">
            <.price observation={Dockd.Pricing.candidate_price(candidate)} />
            <.btn
              size="sm"
              phx-click="choose"
              phx-value-id={@listing.id}
              phx-value-external_id={candidate["external_id"]}
            >
              É este
            </.btn>
          </div>
        </li>
        <li class="dk-match__none">
          <.btn id={"#{@id}-none"} size="sm" phx-click="reject" phx-value-id={@listing.id}>
            Não está na eShop
          </.btn>
          <p :if={@error} class="dk-match__error">{@error}</p>
        </li>
      </ul>
    </div>
    """
  end

  defp match_state(%{match: :review, candidates: [_]}), do: "1 candidato"

  defp match_state(%{match: :review, candidates: candidates}),
    do: "#{length(candidates)} candidatos"

  defp match_state(%{match: :confirmed, title: title}), do: title
  defp match_state(%{match: :rejected}), do: "fora da eShop"

  @sales_status %{
    "preorder" => "Pré-venda",
    "unreleased" => "Não lançado",
    "sales_termination" => "Fora de venda",
    "not_found" => "Não vendido no Brasil"
  }

  defp candidate_meta(candidate) do
    meta([
      if(candidate["bundle"], do: "Pacote", else: "Jogo"),
      enum_label(candidate["platform"]),
      @sales_status[candidate["sales_status"]]
    ])
  end

  @doc """
  SameRow (`maquetes/edicoes.html`, Conferir catálogo): a game and another IGDB entry,
  here as a game of its own, that may be the same one (remaster, expanded game, port).
  `É o mesmo jogo` joins them into the first; `É outro jogo` keeps both and is not asked
  again. Both change the row in place, with `Desfazer` while the screen is open. No
  dialog.
  """
  attr :id, :string, required: true
  attr :review, :map, required: true, doc: "`%{link:, game:, candidate:, state:}` shelf items"
  attr :undo, :boolean, default: false, doc: "whether Desfazer can still put it back"
  attr :error, :string, default: nil

  def same_game(assigns) do
    ~H"""
    <div id={@id} class="dk-same" data-state={@review.state}>
      <div class="dk-row">
        <.poster
          title={@review.game.game.title}
          cover_url={@review.game.game.cover_url}
          size="sm"
          navigate={~p"/jogos/#{@review.game.game.id}"}
        />
        <div>
          <.link navigate={~p"/jogos/#{@review.game.game.id}"} class="dk-row__title">
            {@review.game.game.title}
          </.link>
          <div class="dk-row__meta">{same_meta(@review)}</div>
        </div>
        <div class="dk-row__end">
          <button
            :if={@review.state == :other or (@review.state == :same and @undo)}
            id={"#{@id}-undo"}
            type="button"
            class="dk-link"
            phx-click="undo_same"
            phx-value-id={@review.link.id}
          >
            Desfazer
          </button>
        </div>
      </div>
      <div :if={@review.state == :review} class="dk-same__candidate">
        <.poster
          title={@review.candidate.game.title}
          cover_url={@review.candidate.game.cover_url}
          size="sm"
          navigate={~p"/jogos/#{@review.candidate.game.id}"}
        />
        <div>
          <.link navigate={~p"/jogos/#{@review.candidate.game.id}"} class="dk-row__title">
            {@review.candidate.game.title}
          </.link>
          <div class="dk-row__meta">
            {meta([
              platform_label(@review.candidate.releases),
              @review.candidate.year,
              kind_label(@review.link.kind),
              @review.candidate.status && status_label(@review.candidate.status)
            ])}
          </div>
        </div>
        <div class="dk-row__end">
          <.btn id={"#{@id}-same"} size="sm" phx-click="same" phx-value-id={@review.link.id}>
            É o mesmo jogo
          </.btn>
          <.btn id={"#{@id}-other"} size="sm" phx-click="other" phx-value-id={@review.link.id}>
            É outro jogo
          </.btn>
        </div>
      </div>
      <p :if={@error} class="dk-same__error">{@error}</p>
    </div>
    """
  end

  @same_state %{review: "mesmo jogo?", same: "mesmo jogo", other: "jogos diferentes"}
  @kinds %{expanded: "expandido", port: "port", remaster: "remaster"}

  defp kind_label(kind), do: @kinds[kind]

  defp same_meta(%{game: game, state: state}) do
    meta([
      platform_label(game.releases),
      state != :same && game.year,
      state != :same && game.game.developer,
      @same_state[state]
    ])
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

  @shown_editions 2

  @doc """
  Comprei with editions (`maquetes/edicoes.html`, caminho B): the choices open under the
  row, the standard edition of each platform first, then the editions on sale, cheapest
  first, each with its price and `Comprei esta`, which is the purchase and records that
  price. Past the two cheapest editions, `Mais N edições` shows the rest in place;
  `Cancelar` closes. The same under a row of Comprar and under the game page hero.
  """
  attr :id, :string, required: true
  attr :game_id, :string, required: true
  attr :options, :map, required: true, doc: "from `GameEvents.buy_options/2`"

  def buy_options(assigns) do
    {shown, hidden} = split_choices(assigns.options)
    assigns = assign(assigns, shown: shown, hidden: hidden)

    ~H"""
    <ul id={@id} class="dk-buy__options">
      <li
        :for={choice <- @shown}
        id={"#{@id}-#{choice.release_id}-#{choice.media}"}
        class="dk-buy__option"
      >
        <div>
          <span class="dk-row__title">{choice.name}</span>
          <div class="dk-row__meta">{choice.meta}</div>
        </div>
        <div class="dk-row__end">
          <.price observation={choice.price} />
          <.btn
            size="sm"
            phx-click="buy"
            phx-value-game_id={@game_id}
            phx-value-release_id={choice.release_id}
            phx-value-media={choice.media}
          >
            Comprei esta
          </.btn>
        </div>
      </li>
      <li class="dk-buy__foot">
        <div>
          <button
            :if={@hidden > 0}
            id={"#{@id}-more"}
            type="button"
            class="dk-link"
            phx-click="more_choices"
          >
            {more_editions(@hidden)}
          </button>
          <button type="button" class="dk-link" phx-click="cancel">Cancelar</button>
        </div>
      </li>
    </ul>
    """
  end

  @doc "The link that shows the editions past the cheapest ones."
  def more_editions(1), do: "Mais 1 edição"
  def more_editions(count), do: "Mais #{count} edições"

  defp split_choices(%{choices: choices, all: true}), do: {choices, 0}

  defp split_choices(%{choices: choices}) do
    {standard, editions} = Enum.split_with(choices, &(!&1.edition))
    {shown, hidden} = Enum.split(editions, @shown_editions)
    {standard ++ shown, length(hidden)}
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
  version (when there is a choice) and media, always Digital or Físico regardless of what
  the release declares available, since a manual sighting is how Dockd learns a release is
  sold physically in the first place; then the price seen and where, and the prices already
  seen for the same game underneath.
  """
  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :error, :string, default: nil

  def price_form(assigns) do
    assigns =
      assign(assigns,
        release_options: Enum.map(assigns.form.releases, &{&1.id, release_label(&1)}),
        media_options: Enum.map([:digital, :physical], &{Atom.to_string(&1), enum_label(&1)})
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
  attr :release, :boolean, default: true, doc: "false for a day of the Diário, never red"

  def date_block(assigns) do
    today = assigns.today || Date.utc_today()
    soon = (assigns.release and assigns.date) && Date.diff(assigns.date, today) in 0..14
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
  attr :observation, :map,
    default: nil,
    doc: "a `Purchasing.current_price/3`: an observation or the eShop price, or nil"

  attr :now, DateTime, default: nil
  attr :id, :string, default: nil
  attr :game_id, :string, default: nil
  attr :release_id, :string, default: nil
  attr :open, :boolean, default: false

  def price(assigns) do
    now = assigns.now || DateTime.utc_now()
    highlighted? = assigns.observation && highlighted_price?(assigns.observation)

    stale =
      assigns.observation && !highlighted? &&
        Dockd.Purchasing.stale?(assigns.observation, now, 30)

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

  # eShop prices carry a promotion and a lowest-ever mark; a manual observation never does.
  defp highlighted_price?(observation),
    do: !!(Map.get(observation, :discount_ends_at) || Map.get(observation, :lowest_since))

  attr :observation, :map, default: nil
  attr :stale, :boolean, default: false

  defp price_text(%{observation: nil} = assigns), do: ~H"<b>Sem preço</b>"

  defp price_text(assigns) do
    assigns =
      assign(assigns,
        regular_cents: Map.get(assigns.observation, :regular_cents),
        discount_ends_at: Map.get(assigns.observation, :discount_ends_at),
        lowest_since: Map.get(assigns.observation, :lowest_since)
      )

    ~H"""
    <span class="dk-price__value">
      <s :if={@discount_ends_at}>{money(@regular_cents, @observation.currency)}</s>
      <b>{money(@observation.price_cents, @observation.currency)}</b>
    </span>
    <small>
      <%= cond do %>
        <% @discount_ends_at && @lowest_since -> %>
          até {date_short_pt_br(@discount_ends_at)} · menor preço
        <% @discount_ends_at -> %>
          até {date_short_pt_br(@discount_ends_at)}
        <% @lowest_since -> %>
          menor preço desde {date_short_pt_br(@lowest_since)}
        <% true -> %>
          visto em {date_pt_br(@observation.observed_at)}{if @observation.source,
            do: " · #{@observation.source}"}{if @stale, do: " · desatualizado"}
      <% end %>
    </small>
    """
  end

  defp date_short_pt_br(%DateTime{} = at), do: Calendar.strftime(at, "%d/%m")

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

  # ---------------------------------------------------------------------------
  # Profile (maquetes/perfil-social.html, decided on 28/09/2026)

  @doc """
  ProfileHead (`maquetes/perfil-completo.html`): a monogram of the initials, the name in
  `t-display` with the friend label and `@username`, the bio, place and link the owner
  wrote, and a strip of numbers. At the right, FollowButton or, on one's own profile, the
  Choice of who sees it and Editar perfil. While the profile is closed to the viewer only
  the name and the follow counts remain.
  """
  attr :owner, :map, required: true
  attr :counts, :map, required: true
  attr :relation, :atom, required: true
  attr :links, :boolean, default: true, doc: "false while the profile is closed to the viewer"
  attr :games, :integer, default: nil, doc: "library size, only for a profile the viewer sees"
  attr :year, :integer, required: true
  attr :records, :integer, default: nil, doc: "diary records of `year`, like `games`"

  def profile_head(assigns) do
    ~H"""
    <header id="profile-head" class="dk-profile">
      <span class="dk-avatar" aria-hidden="true">{profile_initials(@owner.name)}</span>
      <div class="dk-profile__who">
        <h1 class="t-display">{@owner.name}</h1>
        <span class="dk-profile__user">@{@owner.username}</span>
        <.friend_mark :if={@relation == :friends} />
      </div>
      <div class="dk-profile__action">
        <.visibility_choice :if={@relation == :self} visibility={@owner.profile_visibility} />
        <.link
          :if={@relation == :self}
          id="profile-edit"
          navigate={~p"/configuracoes"}
          class="dk-btn dk-btn--secondary"
        >
          Editar perfil
        </.link>
        <.follow_button :if={@relation != :self} relation={@relation} username={@owner.username} />
      </div>
      <p :if={@links && @owner.bio} id="profile-bio" class="dk-profile__bio">{@owner.bio}</p>
      <p
        :if={(@links && (@owner.location || @owner.link)) || @relation == :followed_by}
        class="dk-profile__meta"
      >
        <span :if={@links && @owner.location} id="profile-location">{@owner.location}</span>
        <a
          :if={@links && @owner.link}
          id="profile-link"
          href={@owner.link}
          target="_blank"
          rel="nofollow noopener noreferrer"
        >
          {link_host(@owner.link)}
        </a>
        <span :if={@relation == :followed_by} class="dk-profile__you">Segue você</span>
      </p>
      <div id="profile-numbers" class="dk-profile__nums">
        <span :if={@games} id="profile-games"><b>{@games}</b><small>Jogos</small></span>
        <span :if={@records} id="profile-year"><b>{@records}</b><small>Em {@year}</small></span>
        <.link :if={@links} id="profile-following" navigate={~p"/u/#{@owner.username}/seguindo"}>
          <b>{@counts.following}</b><small>Seguindo</small>
        </.link>
        <span :if={!@links} id="profile-following"><b>{@counts.following}</b><small>Seguindo</small></span>
        <.link :if={@links} id="profile-followers" navigate={~p"/u/#{@owner.username}/seguidores"}>
          <b>{@counts.followers}</b><small>{followers_label(@counts.followers)}</small>
        </.link>
        <span :if={!@links} id="profile-followers">
          <b>{@counts.followers}</b><small>{followers_label(@counts.followers)}</small>
        </span>
      </div>
    </header>
    """
  end

  defp followers_label(1), do: "Seguidor"
  defp followers_label(_), do: "Seguidores"

  # The first letter of the first two words of a name: `Daniel Calliari` is `DC`.
  defp profile_initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&(&1 |> String.first() |> String.upcase()))
  end

  defp link_host(link),
    do: link |> URI.parse() |> Map.fetch!(:host) |> String.replace_prefix("www.", "")

  @doc "The friend label beside a name: both accounts follow each other."
  def friend_mark(assigns) do
    ~H"""
    <span class="dk-friend">Amigo</span>
    """
  end

  @doc """
  FollowButton: Seguir, or Seguir de volta when the other account already follows; once
  following it reads Seguindo, and clicking it unfollows in place, with no confirmation.
  A visitor goes to Entrar and comes back to the profile.
  """
  attr :relation, :atom, required: true
  attr :username, :string, required: true
  attr :size, :string, default: "md", values: ~w(md sm)
  attr :id, :string, default: "follow-button"

  def follow_button(%{relation: :visitor} = assigns) do
    ~H"""
    <.link
      id={@id}
      href={DockdWeb.UserAuth.sign_in_path(~p"/u/#{@username}")}
      class={["dk-btn", "dk-btn--primary", @size == "sm" && "dk-btn--sm"]}
    >
      Seguir
    </.link>
    """
  end

  def follow_button(%{relation: relation} = assigns) when relation in [:following, :friends] do
    ~H"""
    <button
      id={@id}
      type="button"
      class={["dk-btn", "dk-btn--secondary", "dk-follow", @size == "sm" && "dk-btn--sm"]}
      data-leave="Deixar de seguir"
      aria-label="Seguindo: deixar de seguir"
      phx-click="unfollow"
      phx-value-username={@username}
    >
      <span>Seguindo</span>
    </button>
    """
  end

  def follow_button(%{relation: :self} = assigns), do: ~H""

  def follow_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class={["dk-btn", "dk-btn--primary", @size == "sm" && "dk-btn--sm"]}
      phx-click="follow"
      phx-value-username={@username}
    >
      {if(@relation == :followed_by, do: "Seguir de volta", else: "Seguir")}
    </button>
    """
  end

  @doc """
  Choice for who sees the profile: Público or Só amigos. The same control everywhere it
  appears (the profile page and Configurações), so `set_visibility` grabs and saves it in
  place, with no separate save button.
  """
  attr :visibility, :atom, required: true
  attr :id, :string, default: "profile-visibility"

  def visibility_choice(assigns) do
    ~H"""
    <form id={@id} phx-change="set_visibility">
      <div class="dk-choice" role="radiogroup" aria-label="Quem vê o perfil">
        <label :for={{value, text} <- [public: "Público", friends: "Só amigos"]}>
          <input type="radio" name="visibility" value={value} checked={@visibility == value} />
          <span>{text}</span>
        </label>
      </div>
    </form>
    """
  end

  @doc """
  PersonRow: an account in a list of followers or followed, with the cover of what it
  plays now in the thumbnail column and FollowButton at the end.
  """
  attr :person, :map, required: true, doc: "from `Dockd.Social.people/3`"

  def person_row(assigns) do
    ~H"""
    <div id={"person-#{@person.user.username}"} class="dk-row dk-person">
      <.poster
        :if={@person.playing}
        title={@person.playing.title}
        cover_url={@person.playing.cover_url}
        size="sm"
      />
      <span :if={!@person.playing} class="dk-poster dk-poster--sm"></span>
      <div>
        <.link navigate={~p"/u/#{@person.user.username}"} class="dk-row__title">
          {@person.user.name} <.friend_mark :if={@person.relation == :friends} />
        </.link>
        <div class="dk-row__meta">
          {meta([
            @person.playing && "Jogando #{@person.playing.title}",
            finished_label(@person.finished)
          ])}
        </div>
      </div>
      <div class="dk-row__end">
        <.follow_button
          id={"follow-#{@person.user.username}"}
          relation={@person.relation}
          username={@person.user.username}
          size="sm"
        />
      </div>
    </div>
    """
  end

  defp finished_label(0), do: nil
  defp finished_label(1), do: "1 zerado"
  defp finished_label(n), do: "#{n} zerados"
end
