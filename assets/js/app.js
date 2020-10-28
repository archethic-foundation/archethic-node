// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import css from "../css/app.css"

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured


import {Socket} from "phoenix"
import LiveSocket from "phoenix_live_view"
import { html } from "diff2html"
import { getTransactionIndex, newTransactionBuilder, derivateAddress } from "uniris"

let Hooks = {}

let scrollAt = () => {
  let scrollTop = document.documentElement.scrollTop || document.body.scrollTop
  let scrollHeight = document.documentElement.scrollHeight || document.body.scrollHeight
  let clientHeight = document.documentElement.clientHeight

  return scrollTop / (scrollHeight - clientHeight) * 100
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

window.openApprovalConfirmation = function() {
  document.querySelector("#proposal_approval_modal").style.display = "block"
}

window.closeApprovalConfirmation = function() {
  document.querySelector("#proposal_approval_modal").style.display = "none";
  document.querySelector("#tx_json").value = ""
  document.querySelector("#tx_index").value = 0
  document.querySelector("#tx_seed").value = ""
  document.querySelector("#form_sign_approval").style.display = "none";
}

window.confirmApproval = function() {
  document.querySelector("#tx_form").style.display = "block";
}

const endpoint = window.location.origin

window.show_form_sign_approval = function() {
  document.querySelector("#form_sign_approval").style.display = "block";
  document.querySelector("#confirmation").style.display = "none";
}

window.signProposalApprovalTransaction = function(e) {
  e.preventDefault()

  const proposalAddress = document.querySelector("#proposal_address").value
  const seed = document.querySelector("#tx_seed").value
  const index = document.querySelector("#tx_index").value

  const txJSON = newTransactionBuilder("code_approval")
    .addRecipient(proposalAddress)
    .build(seed, parseInt(index))
    .toJSON()

    document.querySelector("#tx_viewer").innerText = JSON.stringify(JSON.parse(txJSON), 0, 2)
    document.querySelector("#tx_viewer").style.display = "block"
    document.querySelector("#tx_json").value = txJSON
    document.querySelector("#btn_send_approval").style.display = "inline"
    document.querySelector("#btn_sign_approval").style.display = "none"
}

window.fetchTransactionIndex = function() {
  const seed = document.querySelector("#tx_seed").value
  const firstAddress = derivateAddress(seed, 0)
  getTransactionIndex(firstAddress, endpoint).then((index) => {
    document.querySelector("#tx_index").value = index

    const address = derivateAddress(seed, index + 1)
    document.querySelector("#tx_address").innerText = address
    document.querySelector("#tx_address_info").style.display = "block"
    document.querySelector("#btn_sign_approval").style.display = "block"
  })
}

window.sendApprovalTransaction = function()  {
  const txJSON = document.querySelector("#tx_json").value
  fetch(endpoint + "/api/transaction", {
      method: "POST",
      headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
      },
      body: txJSON
  })
  .then(() => {
    closeApprovalConfirmation()
  })
  .catch(console.error)
}


