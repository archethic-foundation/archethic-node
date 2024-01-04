// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import { } from "./ui";
import {
  initBoxPlotTransactionsAvgDurationChart,
  initNetworkTransactionsCountChart,
  initNetworkTransactionsAvgDurationChart,
  initNodeTransactionsCountChart,
  updateBoxPlotTransactionsAvgDurationChart,
  updateNetworkTransactionsCountChart,
  updateNetworkTransactionsAvgDurationChart,
  updateNodeTransactionsCountChart
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
      outputFormat: "line-by-line",
      highlight: true,
    });
    this.el.innerHTML = diffHtml;
    this.el.style.display = "block";
  },
};

Hooks.Logs = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

Hooks.network_transactions_count_chart = {
  mounted() {
    const chart = initNetworkTransactionsCountChart(this.el.querySelector(".chart"));
    this.handleEvent("network_transactions_count", (stats) => {
      updateNetworkTransactionsCountChart(chart, stats);
    });
  }
};

Hooks.network_transactions_avg_duration_chart = {
  mounted() {
    const chart = initNetworkTransactionsAvgDurationChart(this.el.querySelector(".chart"));
    this.handleEvent("network_transactions_avg_duration", (stats) => {
      updateNetworkTransactionsAvgDurationChart(chart, stats);
    });
  }
};

Hooks.node_transactions_count_chart = {
  mounted() {
    const chart = initNodeTransactionsCountChart(this.el.querySelector(".chart"));
    this.handleEvent("node_transactions_count", (stats) => {
      updateNodeTransactionsCountChart(chart, stats);
    });
  }
};


Hooks.boxplot_transactions_avg_duration = {
  mounted() {
    const chart = initBoxPlotTransactionsAvgDurationChart(this.el.querySelector(".chart"));
    this.handleEvent("boxplot_transactions_avg_duration", (stats) => {
      updateBoxPlotTransactionsAvgDurationChart(chart, stats);
    });
  }
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
      e.target.disabled = true;

      const clipboardId = e.target.getAttribute("data-target");
      const textToCopy = document.querySelector(clipboardId).innerText;

      navigator.clipboard
        .writeText(textToCopy)
        .then(() => {
          e.target.classList.add('check-icon');
          e.target.classList.remove('copy-icon');
        })
        .finally(() => {
          setTimeout(() => {
            e.target.classList.remove('check-icon');
            e.target.classList.add('copy-icon');
            e.target.disabled = false;
          }, 1000);
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
