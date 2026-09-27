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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, StatusMenu, NavSearch},
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
