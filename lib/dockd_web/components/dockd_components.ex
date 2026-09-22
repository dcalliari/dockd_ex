defmodule DockdWeb.DockdComponents do
  @moduledoc "Reusable visual primitives for Dockd screens."

  use Phoenix.Component
  import DockdWeb.CoreComponents, only: [icon: 1, input: 1]
  alias Phoenix.LiveView.JS

  @doc """
  Formats integer cents using the requested currency.

      DockdWeb.DockdComponents.money(19990, "BRL")
  """
  def money(cents, currency) when is_integer(cents) do
    symbol = %{"BRL" => "R$", "USD" => "$", "EUR" => "€"} |> Map.get(currency, currency)
    whole = div(abs(cents), 100)
    fraction = rem(abs(cents), 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""
    "#{sign}#{symbol} #{format_integer(whole)},#{fraction}"
  end

  def money(nil, _currency), do: "Preço não observado"

  @doc """
  Formats a date for Brazilian readers.

      DockdWeb.DockdComponents.date_pt_br(~D[2026-11-18])
  """
  def date_pt_br(nil), do: "Data não informada"
  def date_pt_br(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")

  @doc "Formats today's date for the application context."
  def today_label do
    date = Date.utc_today()

    weekday =
      %{
        1 => "segunda-feira",
        2 => "terça-feira",
        3 => "quarta-feira",
        4 => "quinta-feira",
        5 => "sexta-feira",
        6 => "sábado",
        7 => "domingo"
      }
      |> Map.fetch!(Date.day_of_week(date))

    month =
      %{
        1 => "janeiro",
        2 => "fevereiro",
        3 => "março",
        4 => "abril",
        5 => "maio",
        6 => "junho",
        7 => "julho",
        8 => "agosto",
        9 => "setembro",
        10 => "outubro",
        11 => "novembro",
        12 => "dezembro"
      }
      |> Map.fetch!(date.month)

    "#{weekday}, #{date.day} de #{month} de #{date.year}"
  end

  @doc "Renders the application shell with responsive navigation."
  attr :current, :string, default: nil
  slot :inner_block, required: true
  slot :footer

  def dockd_app_shell(assigns) do
    ~H"""
    <div class="dockd-shell min-h-screen text-base-content">
      <div class="dockd-frame flex min-h-screen">
        <aside class="dockd-sidebar hidden lg:flex lg:flex-col">
          <.brand />
          <nav class="dockd-nav" aria-label="Navegação principal">
            <%= for item <- navigation() do %>
              <.link
                navigate={item.path}
                class={["dockd-nav-link", item.label == @current && "active"]}
              >
                <.icon name={item.icon} class="icon" />
                <span>{item.label}</span>
              </.link>
            <% end %>
          </nav>
          <div class="dockd-sidebar-note">
            <strong>Carteira</strong>
            <span>Switch · Switch 2</span>
            <.link navigate="/carteira">Ver carteira</.link>
          </div>
        </aside>
        <div class="dockd-content">
          <header class="dockd-topbar">
            <div class="flex items-center gap-3">
              <span class="dockd-context">{today_label()}</span>
            </div>
            <div class="dockd-top-actions"><.theme_toggle /></div>
          </header>
          <main class="dockd-main">{render_slot(@inner_block)}</main>
          <div class="dockd-footer">{render_slot(@footer)}</div>
        </div>
      </div>
      <nav class="dockd-mobile-nav" aria-label="Navegação principal">
        <%= for item <- navigation() do %>
          <.link navigate={item.path} class={item.label == @current && "active"}>
            <.icon name={item.icon} class="icon" />
            <span>{item.short}</span>
          </.link>
        <% end %>
      </nav>
    </div>
    """
  end

  @doc "Renders the Dockd wordmark."
  def brand(assigns) do
    ~H"""
    <a href="/" class="dockd-brand">dockd<span>.</span></a>
    """
  end

  @doc "Renders a compact theme switcher."
  def theme_toggle(assigns) do
    ~H"""
    <div class="dockd-top-actions">
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dockd-light"
      >claro</button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dockd-dark"
      >escuro</button>
    </div>
    """
  end

  @doc "Renders a compact screen heading with an optional action."
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="screen-header">
      <div>
        <h1>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
      <div :if={@actions} class="shrink-0">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc "Renders a titled surface for related content."
  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def section_card(assigns) do
    ~H"""
    <section class={[
      "rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm sm:p-6",
      @class
    ]}>
      <h2 class="text-lg font-bold">{@title}</h2><div class="mt-5">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  @doc "Renders a shared section heading."
  attr :title, :string, required: true
  attr :meta, :string, default: nil

  def section_title(assigns) do
    ~H"""
    <div class="section-title">
      <h2>{@title}</h2>
      <span :if={@meta}>{@meta}</span>
    </div>
    """
  end

  @doc "Renders a shared action button."
  attr :variant, :string, default: "secondary", values: ~w(primary secondary ghost danger)
  attr :class, :string, default: ""
  attr :type, :string, default: "button"
  attr :rest, :global
  slot :inner_block, required: true

  def dockd_button(assigns) do
    ~H"""
    <button type={@type} class={["dockd-button", "dockd-button-#{@variant}", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "Renders an empty list row with an optional action."
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :action

  def empty_row(assigns) do
    ~H"""
    <div class="empty-row">
      <strong>{@title}</strong>
      <p :if={@description}>{@description}</p>
      <div :if={@action}>{render_slot(@action)}</div>
    </div>
    """
  end

  @doc "Renders a compact verdict marker."
  attr :label, :string, required: true
  attr :tone, :string, default: "record", values: ~w(buy wait record)

  def verdict_mark(assigns) do
    ~H"""
    <span class={["verdict", "verdict-#{@tone}"]}>{@label}</span>
    """
  end

  @doc "Renders the wallet equation used by the planner."
  attr :balance, :integer, required: true
  attr :reserved, :integer, required: true
  attr :free, :integer, required: true
  attr :currency, :string, default: "BRL"

  def wallet_equation(assigns) do
    ~H"""
    <div class="wallet-line" aria-label="Saldo menos reservas é igual ao livre">
      <div class="wallet-part"><label>Saldo</label><strong>{money(@balance, @currency)}</strong></div>
      <span class="wallet-symbol" aria-hidden="true">−</span>
      <div class="wallet-part">
        <label>Reservas</label><strong>{money(@reserved, @currency)}</strong>
      </div>
      <span class="wallet-symbol" aria-hidden="true">=</span>
      <div class="wallet-part wallet-part-free">
        <label>Livre</label><strong>{money(@free, @currency)}</strong>
      </div>
    </div>
    """
  end

  @doc "Converts domain enum values to Portuguese labels for the interface."
  def enum_label(value) when is_atom(value), do: enum_label(Atom.to_string(value))
  def enum_label("nintendo_exclusive"), do: "Exclusivo Nintendo"
  def enum_label("switch2_exclusive"), do: "Exclusivo Switch 2"
  def enum_label("multiplatform"), do: "Multiplataforma"
  def enum_label("switch"), do: "Switch"
  def enum_label("switch_2"), do: "Switch 2"
  def enum_label("none"), do: "Sem intenção"
  def enum_label("interested"), do: "Interessado"
  def enum_label("want"), do: "Quero comprar"
  def enum_label("planned"), do: "Planejado"
  def enum_label("preordered"), do: "Pré-venda"
  def enum_label("unplayed"), do: "Não jogado"
  def enum_label("playing"), do: "Jogando"
  def enum_label("paused"), do: "Pausado"
  def enum_label("finished"), do: "Terminado"
  def enum_label("abandoned"), do: "Abandonado"
  def enum_label("no"), do: "Fora do backlog"
  def enum_label("backlog"), do: "Backlog"
  def enum_label("active"), do: "Ativo"
  def enum_label("low"), do: "Baixa"
  def enum_label("normal"), do: "Normal"
  def enum_label("high"), do: "Alta"
  def enum_label("physical"), do: "Físico"
  def enum_label("digital"), do: "Digital"
  def enum_label("physical_preferred"), do: "Prefiro físico"
  def enum_label("digital_preferred"), do: "Prefiro digital"
  def enum_label("either"), do: "Qualquer mídia"
  def enum_label("subscription"), do: "Assinatura"
  def enum_label("shared"), do: "Compartilhado"
  def enum_label("borrowed"), do: "Emprestado"
  def enum_label("reserve"), do: "Reservar"
  def enum_label("can_wait"), do: "Pode esperar"
  def enum_label("relaxing"), do: "Relaxante"
  def enum_label("demanding"), do: "Exigente"
  def enum_label("solo"), do: "Solo"
  def enum_label("multi"), do: "Multijogador"
  def enum_label("both"), do: "Solo e multi"

  def enum_label(value) when is_binary(value),
    do: value |> String.replace("_", " ") |> String.capitalize()

  @doc "Parses a Brazilian reais input into integer cents."
  def parse_money(nil), do: {:ok, nil}
  def parse_money(value) when is_integer(value), do: {:ok, value}

  def parse_money(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:ok, nil}

      Regex.match?(~r/^\d{1,3}(\.\d{3})*,\d{2}$/, value) ->
        parse_digits(String.replace(value, ".", "") |> String.replace(",", "."))

      Regex.match?(~r/^\d+(,\d{1,2})?$/, value) ->
        parse_digits(String.replace(value, ",", "."))

      Regex.match?(~r/^\d+\.\d{1,2}$/, value) ->
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

  @doc "Renders a reais input while the domain keeps integer cents."
  attr :field, :any, required: true
  attr :label, :string, required: true
  attr :id, :string, default: nil

  def money_input(assigns) do
    value = assigns.field.value

    display =
      if is_integer(value), do: money(value, "BRL") |> String.replace("R$ ", ""), else: value

    assigns = assign(assigns, :display, display)

    ~H"""
    <.input
      field={@field}
      type="text"
      inputmode="decimal"
      label={@label}
      id={@id}
      value={@display}
      placeholder="199,90"
    />
    """
  end

  @doc "Renders a platform badge."
  attr :platform, :atom, required: true

  def platform_badge(assigns) do
    label = if assigns.platform in [:switch_2, :switch2], do: "Switch 2", else: "Switch"
    assigns = assign(assigns, :label, label)

    ~H"""
    <span class="badge badge-neutral">{@label}</span>
    """
  end

  @doc "Renders a media format badge."
  attr :media, :atom, required: true

  def media_badge(assigns) do
    label =
      %{physical: "físico", digital: "digital", key_card: "key-card"}
      |> Map.get(assigns.media, to_string(assigns.media))

    assigns = assign(assigns, :label, label)

    ~H"""
    <span class="badge badge-outline">{@label}</span>
    """
  end

  @doc "Renders a compact status marker."
  attr :label, :string, required: true

  attr :tone, :string,
    default: "neutral",
    values: ~w(primary secondary success warning error info neutral)

  def status_mark(assigns),
    do: ~H"""
    <span class="inline-flex items-center gap-1.5 text-xs font-semibold text-base-content/70">
      <span class={["size-2 rounded-full", "bg-#{@tone}"]}></span>{@label}
    </span>
    """

  @doc "Renders a dated value and marks old observations."
  attr :value, :integer, required: true
  attr :currency, :string, default: "BRL"
  attr :observed_at, :any, required: true
  attr :stale, :boolean, default: false

  def dated_value(assigns),
    do: ~H"""
    <div>
      <p class={["font-bold tabular-nums", @stale && "text-error"]}>{money(@value, @currency)}</p><p class="text-xs text-base-content/60">
        observado em {date_pt_br(@observed_at)}
        <span :if={@stale} class="font-semibold text-error">· desatualizado</span>
      </p>
    </div>
    """

  @doc "Renders one release in a date ordered calendar."
  attr :title, :string, required: true
  attr :date, :any, required: true
  attr :platform, :atom, required: true
  attr :media, :atom, required: true

  def release_calendar_item(assigns),
    do: ~H"""
    <div class="flex min-w-0 items-center gap-3">
      <time class="w-14 shrink-0 rounded-xl bg-primary p-2 text-center text-primary-content"><b class="block text-lg">{Calendar.strftime(
        @date,
        "%d"
      )}</b><small>{Calendar.strftime(@date, "%b") |> String.upcase()}</small></time><div class="min-w-0">
        <p class="truncate font-bold">{@title}</p><div class="mt-1 flex flex-wrap gap-1">
          <.platform_badge platform={@platform} /><.media_badge media={@media} />
        </div>
      </div>
    </div>
    """

  @doc "Renders a designed cover placeholder when artwork is unavailable."
  attr :title, :string, required: true
  attr :cover_url, :string, default: nil
  attr :class, :string, default: ""

  def game_cover(assigns) do
    initials = assigns.title |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)
    assigns = assign(assigns, :initials, String.upcase(initials))

    ~H"""
    <div class={["dockd-cover", @class]}>
      <%= if @cover_url && @cover_url != "" do %>
        <img src={@cover_url} alt={@title} loading="lazy" />
      <% else %>
        <div class="cover-placeholder"><span class="display">{@initials}</span></div>
      <% end %>
    </div>
    """
  end

  @doc "Renders an empty collection message."
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :action

  def empty_state(assigns),
    do: ~H"""
    <div class="rounded-2xl border border-dashed border-base-content/20 p-8 text-center">
      <p class="font-bold">{@title}</p><p :if={@description} class="mt-2 text-sm text-base-content/60">
        {@description}
      </p><div :if={@action} class="mt-4">{render_slot(@action)}</div>
    </div>
    """

  defp navigation,
    do: [
      %{label: "Planejador", short: "Hoje", path: "/", icon: "hero-home"},
      %{label: "Biblioteca", short: "Jogos", path: "/biblioteca", icon: "hero-book-open"},
      %{label: "Descobrir", short: "Descobrir", path: "/catalogo", icon: "hero-sparkles"},
      %{label: "Carteira", short: "Carteira", path: "/carteira", icon: "hero-wallet"}
    ]

  defp format_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end
end
