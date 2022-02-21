
// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import { } from "../css/app.scss"
import { } from './ui'
import * as metric_config_obj from  './metric_config.js';

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured

import { Socket } from "phoenix"
import LiveSocket from "phoenix_live_view"
import { html } from "diff2html"
import hljs from "highlight.js"

// add alpinejs
import Alpine from "alpinejs";
window.Alpine = Alpine;
Alpine.start();

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

  updated() {
    hljs.highlightBlock(this.el);
  }
}

Hooks.InfiniteScroll = {
  page() { return this.el.dataset.page },
  mounted() {
    this.pending = this.page()
    window.addEventListener("scroll", e => {
      if (this.pending == this.page() && scrollAt() > 90) {
        this.pending = this.page() + 1
        this.pushEvent("load-more", {})
      }

    })
  },
  reconnected() { this.pending = this.page() },
  updated() { this.pending = this.page() }
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

//metric dashboard hook /metrics/dashboard
Hooks.network_charts = {
  mounted() {

    var network_metric_obj = metric_config_obj.create_network_live_visuals();
    this.handleEvent("network_points", ({
      points
    }) => {
      console.log(points);
      points = metric_config_obj.structure_metric_points(points)
     
      network_metric_obj = metric_config_obj.update_network_live_visuals(network_metric_obj , points);
      
    });

  }
}


Hooks.explorer_charts = {

  mounted() {
    var explorer_metric_obj = metric_config_obj.create_explorer_live_visuals();

      this.handleEvent("explorer_stats_points", ({
        points
      }) => {
        console.log(points);
        points = metric_config_obj.structure_metric_points(points)
        explorer_metric_obj = metric_config_obj.update_explorer_live_visuals(explorer_metric_obj , points);    
      });
  }
}



let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken },
  dom: {
    onBeforeElUpdated(from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to);
      }
    }
  },
});

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket

window.diff2html = html

// disable "confirm form resubmission" on back button click
if (window.history.replaceState) {
  window.history.replaceState(null, null, window.location.href);
}