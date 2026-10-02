// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/dockd"
import topbar from "../vendor/topbar"

// O tema segue o sistema operacional: nenhum estado guardado no navegador.

// StatusMenu (DockdComponents.status_menu): com mouse, apontar abre as opções e clicar na
// etiqueta atual desmarca. No toque não há apontar: o primeiro toque abre, o segundo desmarca.
// `data-open` é o servidor pedindo o menu aberto (URL com abrir, ou a pergunta da versão).
const canHover = window.matchMedia("(hover: hover)")

const StatusMenu = {
  mounted() {
    this.open = false
    this.el.addEventListener("click", event => {
      const current = event.target.closest(".dk-status-menu__current")
      if (!current) {
        if (event.target.closest("[phx-click]")) this.open = false
        return
      }
      const shown = this.open || this.serverOpen() || canHover.matches
      if (current.hasAttribute("phx-click") && shown) {
        this.open = false
        return
      }
      event.preventDefault()
      event.stopPropagation()
      this.open = !(this.open || this.serverOpen())
      if (!this.open && this.serverOpen()) this.pushEvent("close_status", {})
      this.apply()
    })
    this.closeOutside = event => {
      if (this.el.contains(event.target)) return
      if (this.serverOpen()) this.pushEvent("close_status", {})
      if (this.open) {
        this.open = false
        this.apply()
      }
    }
    document.addEventListener("click", this.closeOutside)
    this.apply()
  },
  updated() {
    this.apply()
  },
  destroyed() {
    document.removeEventListener("click", this.closeOutside)
  },
  serverOpen() {
    return this.el.dataset.open === "true"
  },
  apply() {
    const open = this.open || this.serverOpen()
    this.el.classList.toggle("is-open", open)
    this.el.querySelector(".dk-status-menu__current")?.setAttribute("aria-expanded", String(open))
  },
}

const NavSearch = {
  mounted() {
    const nav = this.el.closest(".dk-nav")
    const input = nav?.querySelector(".dk-nav__search input")
    this.el.addEventListener("click", () => {
      nav.classList.add("dk-nav--searching")
      input?.focus()
    })
    input?.addEventListener("blur", () => {
      if (!input.value) nav.classList.remove("dk-nav--searching")
    })
  },
}

// FavoriteSlots (ProfileLive): the owner's four favorites. Dragging a cover onto another
// position (mouse after a few pixels, touch after a long press so scrolling still works)
// or pressing the arrow keys on it sends `place_favorite`; the server swaps or moves.
const FavoriteSlots = {
  mounted() {
    const grid = this.el
    let pending = null
    let active = null
    let timer = null
    let moved = false
    this.focusGame = null

    const slotAt = (x, y) => document.elementFromPoint(x, y)?.closest(".dk-fav-slot")
    const clearOver = () => grid.querySelectorAll(".is-over").forEach(el => el.classList.remove("is-over"))
    const activate = () => {
      if (!pending) return
      active = pending
      active.card.classList.add("is-dragging")
      grid.classList.add("is-sorting")
    }
    const finish = event => {
      clearTimeout(timer)
      if (active) {
        moved = true
        const target = slotAt(event.clientX, event.clientY)
        if (target && target !== active.card) {
          this.pushEvent("place_favorite", {game_id: active.card.dataset.gameId, position: target.dataset.position})
        }
        active.card.classList.remove("is-dragging")
        grid.classList.remove("is-sorting")
        clearOver()
      }
      pending = active = null
    }

    grid.addEventListener("dragstart", event => event.preventDefault())
    grid.addEventListener("pointerdown", event => {
      const card = event.target.closest(".dk-fav-slot[data-game-id]")
      if (!card || event.target.closest(".dk-fav-remove") || event.button > 0) return
      moved = false
      pending = {card, x: event.clientX, y: event.clientY, touch: event.pointerType !== "mouse"}
      if (pending.touch) timer = setTimeout(activate, 350)
    })
    grid.addEventListener("pointermove", event => {
      if (!pending) return
      if (!active) {
        const distance = Math.hypot(event.clientX - pending.x, event.clientY - pending.y)
        if (pending.touch && distance > 10) {
          clearTimeout(timer)
          pending = null
        } else if (!pending.touch && distance > 6) {
          activate()
        }
      }
      if (active) {
        clearOver()
        const over = slotAt(event.clientX, event.clientY)
        if (over && over !== active.card) over.classList.add("is-over")
      }
    })
    grid.addEventListener("pointerup", finish)
    grid.addEventListener("pointercancel", finish)
    grid.addEventListener("touchmove", event => { if (active) event.preventDefault() }, {passive: false})
    grid.addEventListener("click", event => {
      if (moved) {
        event.preventDefault()
        event.stopPropagation()
        moved = false
      }
    }, true)
    grid.addEventListener("keydown", event => {
      const card = event.target.closest(".dk-fav-slot[data-game-id]")
      const step = {ArrowLeft: -1, ArrowRight: 1}[event.key]
      if (!card || !step) return
      const position = Number(card.dataset.position) + step
      if (position < 1 || position > 4) return
      event.preventDefault()
      this.focusGame = card.dataset.gameId
      this.pushEvent("place_favorite", {game_id: card.dataset.gameId, position: String(position)})
    })
  },
  updated() {
    if (!this.focusGame) return
    this.el.querySelector(`.dk-fav-slot[data-game-id="${this.focusGame}"] a`)?.focus()
    this.focusGame = null
  },
}

const FavoritePicker = {
  mounted() {
    this.returnFocusTo = document.activeElement
    this.search = this.el.querySelector("#favorite-search")
    this.search?.focus()
    this.el.addEventListener("keydown", event => {
      if (event.key === "Escape") {
        event.preventDefault()
        this.pushEvent("close_picker", {})
        return
      }
      if (event.key !== "Tab") return

      const focusable = [...this.el.querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )].filter(element => element.getClientRects().length)
      const first = focusable[0]
      const last = focusable[focusable.length - 1]

      if (event.shiftKey && (document.activeElement === first || !this.el.contains(document.activeElement))) {
        event.preventDefault()
        last?.focus()
      } else if (!event.shiftKey && (document.activeElement === last || !this.el.contains(document.activeElement))) {
        event.preventDefault()
        first?.focus()
      }
    })
  },
  destroyed() {
    if (this.returnFocusTo?.isConnected) this.returnFocusTo.focus()
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, StatusMenu, NavSearch, FavoriteSlots, FavoritePicker},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#e60012"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
