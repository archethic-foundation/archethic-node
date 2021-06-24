// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import {} from "../css/app.scss"
import {} from './ui'

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured

import {Socket} from "phoenix"
import LiveSocket from "phoenix_live_view"
import { html } from "diff2html"
import hljs from "highlight.js"

let Hooks = {}

let scrollAt = () => {
  let scrollTop = document.documentElement.scrollTop || document.body.scrollTop
  let scrollHeight = document.documentElement.scrollHeight || document.body.scrollHeight
  let clientHeight = document.documentElement.clientHeight

  return scrollTop / (scrollHeight - clientHeight) * 100
}

Hooks.CodeViewer = {
  mounted() {
    hljs.highlightBlock(this.el);
  },

  updated(){ 
    hljs.highlightBlock(this.el);
  }
}

Hooks.InfiniteScroll = {
  page() { return this.el.dataset.page },
  mounted(){
    this.pending = this.page()
    window.addEventListener("scroll", e => {
      if(this.pending == this.page() && scrollAt() > 90){
        this.pending = this.page() + 1
        this.pushEvent("load-more", {})
      }
      
    })
  },
  reconnected(){ this.pending = this.page() },
  updated(){ this.pending = this.page() }
}

Hooks.Diff = {
  mounted() {
    const diff = this.el.innerText
    const diffHtml = diff2html(diff, {
        drawFileList: true,
        matching: 'lines',
        outputFormat: 'side-by-side',
        highlight: true
    });
    document.querySelector('#diff').innerHTML = diffHtml;
  }
}

Hooks.Logs = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight;
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: {_csrf_token: csrfToken}});

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket

window.diff2html = html


