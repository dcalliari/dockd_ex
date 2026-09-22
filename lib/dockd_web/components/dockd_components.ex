defmodule DockdWeb.DockdComponents do
  @moduledoc "Reusable visual primitives for Dockd screens."

  use Phoenix.Component
  import DockdWeb.CoreComponents, only: [input: 1]
  alias Phoenix.LiveView.JS

  @doc "Formats integer cents using the requested currency."
  def money(cents, currency) when is_integer(cents) do
    symbol = %{"BRL" => "R$", "USD" => "$", "EUR" => "€"} |> Map.get(currency, currency)
    whole = div(abs(cents), 100)
    fraction = rem(abs(cents), 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""
    "#{sign}#{symbol} #{format_integer(whole)},#{fraction}"
  end

  def money(nil, _currency), do: "Preço não observado"

  @doc "Formats a date for Brazilian readers."
  def date_pt_br(nil), do: "Data não informada"
  def date_pt_br(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")

  @doc "Renders the application shell with responsive top navigation."
  attr :current, :string, default: nil
  slot :inner_block, required: true
  slot :footer

  def dockd_app_shell(assigns) do
    ~H"""
    <div class="dockd-shell min-h-screen text-base-content">
      <header class="dockd-topbar">
        <div class="dockd-topbar-inner">
          <.brand />
          <nav class="dockd-nav" aria-label="Navegação principal">
            <%= for item <- navigation() do %>
              <.link
                navigate={item.path}
                class="dockd-nav-link"
                data-active={to_string(item.label == @current)}
              >
                {item.label}
              </.link>
            <% end %>
          </nav>
          <.theme_toggle />
        </div>
      </header>
      <main class="dockd-main">{render_slot(@inner_block)}</main>
      <footer class="dockd-footer">{render_slot(@footer)}</footer>
    </div>
    """
  end

  @doc "Renders the Dockd wordmark and home link."
  def brand(assigns) do
    ~H"""
    <.link navigate="/" class="dockd-brand" aria-label="Dockd, abrir planejador">
      <span class="dockd-brand-mark" aria-hidden="true"></span>
      <span>dockd</span>
    </.link>
    """
  end

  @doc "Renders a compact theme switcher."
  def theme_toggle(assigns) do
    ~H"""
    <div class="dockd-theme-toggle" aria-label="Tema">
      <button
        type="button"
        aria-label="Usar tema claro"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dockd-light"
      >Claro</button>
      <button
        type="button"
        aria-label="Usar tema escuro"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dockd-dark"
      >Escuro</button>
    </div>
    """
  end

  @doc "Renders a page title with an optional action slot."
  attr :title, :string, required: true
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="dockd-page-header">
      <h1 class="dockd-page-title">{@title}</h1>
      <div :if={@actions != []}>{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc "Renders a titled surface for related content."
  attr :title, :string, required: true
  attr :class, :any, default: ""
  slot :inner_block, required: true

  def section_card(assigns) do
    ~H"""
    <section class={["dockd-panel", @class]}>
      <h2 class="dockd-section-title">{@title}</h2>
      <div class="mt-5">{render_slot(@inner_block)}</div>
    </section>
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

  @doc "Renders a platform marker."
  attr :platform, :atom, required: true

  def platform_badge(assigns) do
    label = if assigns.platform in [:switch_2, :switch2], do: "Switch 2", else: "Switch"
    assigns = assign(assigns, :label, label)

    ~H"""
    <span class="dockd-tag">{@label}</span>
    """
  end

  @doc "Renders a media format marker."
  attr :media, :atom, required: true

  def media_badge(assigns) do
    label =
      %{physical: "físico", digital: "digital", key_card: "key-card"}
      |> Map.get(assigns.media, to_string(assigns.media))

    assigns = assign(assigns, :label, label)

    ~H"""
    <span class="dockd-tag">{@label}</span>
    """
  end

  @doc "Renders a compact status marker."
  attr :label, :string, required: true
  attr :tone, :string, default: "neutral"

  def status_mark(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 text-xs font-bold text-base-content/70">
      <span class={["size-1.5 rounded-full", "bg-#{@tone}"]}></span>
      {@label}
    </span>
    """
  end

  @doc "Renders a dated value and marks old observations."
  attr :value, :integer, required: true
  attr :currency, :string, default: "BRL"
  attr :observed_at, :any, required: true
  attr :stale, :boolean, default: false

  def dated_value(assigns) do
    ~H"""
    <div>
      <p class={["dockd-value font-bold", @stale && "text-error"]}>{money(@value, @currency)}</p>
      <p class="dockd-meta">
        observado em {date_pt_br(@observed_at)}<span :if={@stale} class="font-bold text-error"> · desatualizado</span>
      </p>
    </div>
    """
  end

  @doc "Renders one release in a date ordered calendar."
  attr :title, :string, required: true
  attr :date, :any, required: true
  attr :platform, :atom, required: true
  attr :media, :atom, required: true

  def release_calendar_item(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-3">
      <time class="w-14 shrink-0 border-l-2 border-primary py-1 pl-2">
        <b class="dockd-value block text-lg">{Calendar.strftime(@date, "%d")}</b>
        <small class="dockd-meta">{Calendar.strftime(@date, "%b") |> String.upcase()}</small>
      </time>
      <div class="min-w-0">
        <p class="truncate font-bold">{@title}</p>
        <div class="mt-1 flex flex-wrap gap-1">
          <.platform_badge platform={@platform} /><.media_badge media={@media} />
        </div>
      </div>
    </div>
    """
  end

  @doc "Renders a real cover or a quiet title placeholder."
  attr :title, :string, required: true
  attr :cover_url, :string, default: nil
  attr :class, :any, default: ""

  def game_cover(assigns) do
    ~H"""
    <div class={["dockd-cover", @class]}>
      <%= if @cover_url && @cover_url != "" do %>
        <img src={@cover_url} alt={"Capa de #{@title}"} loading="lazy" />
      <% else %>
        <div class="dockd-cover-placeholder">{@title}</div>
      <% end %>
    </div>
    """
  end

  @doc "Renders a concise empty collection message."
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="dockd-empty py-5">
      <p>{@title}</p>
      <p :if={@description} class="mt-1">{@description}</p>
      <div :if={@action} class="mt-3">{render_slot(@action)}</div>
    </div>
    """
  end

  defp navigation,
    do: [
      %{label: "Planejador", path: "/"},
      %{label: "Biblioteca", path: "/biblioteca"},
      %{label: "Catálogo", path: "/catalogo"},
      %{label: "Carteira", path: "/carteira"}
    ]

  defp format_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end
end
