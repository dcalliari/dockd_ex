defmodule DockdWeb.DockdComponents do
  @moduledoc "Reusable visual primitives for Dockd screens."

  use Phoenix.Component
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

  @doc "Renders the application shell with responsive navigation."
  attr :current, :string, default: nil
  slot :inner_block, required: true

  def dockd_app_shell(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 text-base-content">
      <div class="mx-auto flex min-h-screen max-w-[1440px]">
        <aside class="hidden w-64 shrink-0 border-r border-base-content/10 bg-base-100 p-6 lg:flex lg:flex-col">
          <.brand />
          <nav class="mt-12 space-y-2" aria-label="Navegação principal">
            <%= for item <- navigation() do %>
              <.link
                navigate={item.path}
                class={[
                  "flex min-h-11 items-center rounded-xl px-4 text-sm font-semibold transition-colors hover:bg-base-200",
                  item.label == @current && "bg-primary text-primary-content hover:bg-primary"
                ]}
              >
                {item.label}
              </.link>
            <% end %>
          </nav>
          <p class="mt-auto text-xs text-base-content/50">comprar menos no escuro.</p>
        </aside>
        <div class="min-w-0 flex-1 pb-24 lg:pb-0">
          <header class="sticky top-0 z-20 border-b border-base-content/10 bg-base-100/90 px-4 py-4 backdrop-blur sm:px-8">
            <div class="flex items-center justify-between">
              <div class="lg:hidden"><.brand /></div>
              <div class="ml-auto"><.theme_toggle /></div>
            </div>
          </header>
          <main class="px-4 py-8 sm:px-8 lg:px-12 lg:py-12">{render_slot(@inner_block)}</main>
        </div>
      </div>
      <nav
        class="fixed inset-x-0 bottom-0 z-30 border-t border-base-content/10 bg-base-100/95 px-3 py-2 backdrop-blur lg:hidden"
        aria-label="Navegação principal"
      >
        <div class="mx-auto flex max-w-lg justify-around gap-2">
          <%= for item <- navigation() do %>
            <.link
              navigate={item.path}
              class={[
                "flex min-h-11 min-w-20 flex-col items-center justify-center rounded-xl px-3 text-xs font-semibold transition-colors hover:bg-base-200",
                item.label == @current && "bg-primary text-primary-content hover:bg-primary"
              ]}
            >
              {item.label}
            </.link>
          <% end %>
        </div>
      </nav>
    </div>
    """
  end

  @doc "Renders the Dockd wordmark."
  def brand(assigns) do
    ~H"""
    <a href="/catalogo" class="display text-2xl font-black tracking-tight">dockd<span class="text-primary">.</span></a>
    """
  end

  @doc "Renders a compact theme switcher."
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-1 rounded-xl border border-base-content/10 bg-base-200 p-1">
      <button
        type="button"
        class="min-h-9 rounded-lg px-3 text-xs font-semibold hover:bg-base-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dockd-light"
      >Claro</button>
      <button
        type="button"
        class="min-h-9 rounded-lg px-3 text-xs font-semibold hover:bg-base-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dockd-dark"
      >Escuro</button>
    </div>
    """
  end

  @doc "Renders a page title with an optional action slot."
  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-end justify-between gap-5">
      <div class="min-w-0">
        <p :if={@eyebrow} class="eyebrow text-xs font-bold uppercase text-primary">{@eyebrow}</p>
        <h1 class="display mt-2 text-4xl font-black tracking-tight sm:text-5xl">{@title}</h1>
        <p :if={@description} class="mt-3 max-w-2xl text-base leading-relaxed text-base-content/70">
          {@description}
        </p>
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

  @doc "Renders a financial metric card."
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :currency, :string, default: "BRL"
  attr :detail, :string, default: nil
  attr :tone, :string, default: "primary"

  def money_card(assigns) do
    ~H"""
    <article class="rounded-2xl bg-neutral p-5 text-neutral-content shadow-sm sm:p-6">
      <p class="text-sm opacity-70">{@label}</p><p class={[
        "mt-4 text-3xl font-black tabular-nums",
        @tone == "primary" && "text-primary-content"
      ]}>
        {money(@value, @currency)}
      </p><p :if={@detail} class="mt-2 text-sm opacity-70">{@detail}</p>
    </article>
    """
  end

  @doc "Renders a compact stat card."
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :detail, :string, default: nil

  def stat_card(assigns),
    do: ~H"""
    <article class="rounded-2xl border border-base-content/10 bg-base-100 p-5">
      <p class="text-sm text-base-content/60">{@label}</p><p class="mt-3 text-3xl font-black tabular-nums">
        {@value}
      </p><p :if={@detail} class="mt-2 text-sm text-base-content/60">{@detail}</p>
    </article>
    """

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

  @doc "Renders a status chip with an intent tone."
  attr :label, :string, required: true

  attr :tone, :string,
    default: "neutral",
    values: ~w(primary secondary success warning error info neutral)

  def status_chip(assigns),
    do: ~H"""
    <span class={["badge", "badge-#{@tone}"]}>{@label}</span>
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

  @doc "Renders the backlog pressure indicator."
  attr :count, :integer, required: true
  attr :label, :string, default: "parados"

  def backlog_pressure(assigns),
    do: ~H"""
    <div class="rounded-xl border-l-4 border-warning bg-warning/10 p-4">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <p class="text-2xl font-black tabular-nums">
          {@count} <span class="text-base font-normal">{@label}</span>
        </p><.status_chip label="atenção" tone="warning" />
      </div><p class="mt-2 text-sm text-base-content/70">
        Antes de comprar, há jogos esperando sua vez.
      </p>
    </div>
    """

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
    do: [%{label: "Catálogo", path: "/catalogo"}, %{label: "Biblioteca", path: "/biblioteca"}]

  defp format_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end
end
