// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import {} from "../css/app.scss";
import {} from "./ui";
import {
  initializeNbTransactionGraph,
  updateNbTransactionGraph,
  initializeValidationDurationGraph,
  updateValidationDurationGraph
} from "./metric_config.js";
import { createWorldmap, updateWorldmap } from "./worldmap";

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured

import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { html } from "diff2html";
import hljs from "highlight.js";

// add alpinejs
import Alpine from "alpinejs";
window.Alpine = Alpine;
Alpine.start();

let Hooks = {};

let scrollAt = () => {
  let scrollTop = document.documentElement.scrollTop || document.body.scrollTop;
  let scrollHeight =
    document.documentElement.scrollHeight || document.body.scrollHeight;
  let clientHeight = document.documentElement.clientHeight;

  return (scrollTop / (scrollHeight - clientHeight)) * 100;
};

Hooks.CodeViewer = {
  mounted() {
    hljs.highlightBlock(this.el);
  },

  updated() {
    hljs.highlightBlock(this.el);
  },
};

Hooks.InfiniteScroll = {
  page() {
    return this.el.dataset.page;
  },
  mounted() {
    this.pending = this.page();
    window.addEventListener("scroll", (e) => {
      if (this.pending == this.page() && scrollAt() > 90) {
        this.pending = this.page() + 1;
        this.pushEvent("load-more", {});
      }
    });
  },
  reconnected() {
    this.pending = this.page();
  },
  updated() {
    this.pending = this.page();
  },
};

Hooks.Diff = {
  mounted() {
    const diff = this.el.innerText;
    const diffHtml = diff2html(diff, {
      drawFileList: true,
      matching: "lines",
      outputFormat: "side-by-side",
      highlight: true,
    });
    document.querySelector("#diff").innerHTML = diffHtml;
  },
};

Hooks.Logs = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

//metric dashboard hook /metrics/dashboard
Hooks.network_charts = {
  mounted() {
    const nbTransactionEl = this.el.querySelector("#nb_transactions")
    const validationDurationEl = this.el.querySelector("#validation_duration")
    
    const txGraph = initializeNbTransactionGraph(nbTransactionEl);
    const validationDurationGraph = initializeValidationDurationGraph(validationDurationEl);

    this.handleEvent("network_updates", ({ nb_transactions, validation_duration }) => {
      updateNbTransactionGraph(txGraph, nb_transactions);
      updateValidationDurationGraph(validationDurationGraph, validation_duration);
    });
  },
};

Hooks.worldmap = {
  mounted() {
    this.handleEvent("worldmap_init_datas", ({ worldmap_datas }) => {
      if (worldmap_datas.length > 0) createWorldmap(worldmap_datas);
    });

    this.handleEvent("worldmap_update_datas", ({ worldmap_datas }) => {
      if (worldmap_datas.length > 0) updateWorldmap(worldmap_datas);
    });
  },
};

Hooks.CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const clipboardId = e.target.id;

      const textToCopy = document.getElementById(clipboardId).innerHTML;

      navigator.clipboard
        .writeText(textToCopy)
        .then(() => {
          e.target.innerText = "Copied !";
          e.target.disabled = true;
        })
        .catch(() => {
          e.target.innerText = "Failed !";
          e.target.disabled = true;
        })
        .finally(() => {
          setTimeout(() => {
            e.target.innerText = "Copy";
            e.target.disabled = false;
          }, 3000);
        });
    });
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken },
  dom: {
    onBeforeElUpdated(from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to);
      }
    },
  },
});

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket;

window.diff2html = html;

// disable "confirm form resubmission" on back button click
if (window.history.replaceState) {
  window.history.replaceState(null, null, window.location.href);
}
