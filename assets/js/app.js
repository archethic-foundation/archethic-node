// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import { } from "../css/app.scss"
import { } from './ui'

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

function generateEchartObjects(heading , echartContainer ,  x_axis_data){
  var y_axis_data = [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0, 0, 0, 0, 0, 0, 0, 0];
  var chart = echarts.init(document.getElementById(echartContainer));

  var option= {
  
    grid: {
      left: '10%',
      right: '5%',
      bottom: '10%',
      top:"20%"
    },
    title: {
      left: 'center',
      text: ` ${heading}(ms)`
    },
    xAxis: {
      type: 'category',
      boundaryGap: false,
      data: x_axis_data,
      show:false,
      splitLine: {
        show: true,
        lineStyle:{color:"lightgrey",width:0.5}
      }
    },
    yAxis: {
      boundaryGap: [0, '50%'],
      type: 'value',
      splitLine: {
        show: true,
        lineStyle:{color:"lightgrey",width:0.5}
      },
      
    },
    series: [
      {
        type: 'line',
        symbol: 'none',
         itemStyle: {
          color: 'rgb(0, 164, 219,0.8)'
        },
        data: y_axis_data
      }
    ]
  };

  option && chart.setOption(option);
  return { chart: chart , ydata: y_axis_data};

}

Hooks.node_charts = {
  mounted() {
    var seconds_after_loading_of_this_graph = 0;
    var x_axis_data =  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    
    var election_validation_node=generateEchartObjects('Election Duration-Validation Nodes','echartContainer0',x_axis_data)
    var storage_validation_node=generateEchartObjects('Election Duration-Storage Nodes','echartContainer1',x_axis_data)
    var mining_pending_transaction=generateEchartObjects('Mining Pending Transaction' , 'echartContainer2',x_axis_data)
    var proof_of_works = generateEchartObjects( 'Duration(ms):Proof of Work ','echartContainer3',x_axis_data)
    var full_transaction_validation = generateEchartObjects('Full Transaction Validation','echartContainer4',x_axis_data)
    var contract_parsing = generateEchartObjects('Duration: Contract Parsing','echartContainer5',x_axis_data)
 

  
    this.handleEvent("node_points", ({
      points
    }) => {
      console.log(points);
      x_axis_data.push(++seconds_after_loading_of_this_graph);
      election_validation_node.ydata.push(points.evn)

      election_validation_node.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data: election_validation_node.ydata
        }]
      });

      storage_validation_node.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data: storage_validation_node.ydata
        }]
      });

      mining_pending_transaction.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  mining_pending_transaction.ydata
        }]
      });
      proof_of_works.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  proof_of_works.ydata
        }]
      });
      full_transaction_validation.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  full_transaction_validation.ydata
        }]
      });

      contract_parsing.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  contract_parsing.ydata
        }]
      });
    });

  }
}

Hooks.network_charts = {
  mounted() {
    var seconds_after_loading_of_this_graph = 0;
    var x_axis_data =  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    
    var election_validation_node=generateEchartObjects('Election Duration-Validation Nodes','echartContainer0',x_axis_data)
    var storage_validation_node=generateEchartObjects('Election Duration-Storage Nodes','echartContainer1',x_axis_data)
    var mining_pending_transaction=generateEchartObjects('Mining Pending Transaction' , 'echartContainer2',x_axis_data)
    var proof_of_works = generateEchartObjects( 'Duration(ms):Proof of Work ','echartContainer3',x_axis_data)
    var full_transaction_validation = generateEchartObjects('Full Transaction Validation','echartContainer4',x_axis_data)
    var contract_parsing = generateEchartObjects('Duration: Contract Parsing','echartContainer5',x_axis_data)
 
  
    this.handleEvent("network_points", ({
      points
    }) => {
      points = structure_metric_points(points)
      console.log(points);
      x_axis_data.push(++seconds_after_loading_of_this_graph);
      // election_validation_node.ydata.push(points.evn)

      election_validation_node.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data: election_validation_node.ydata
        }]
      });

      storage_validation_node.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data: storage_validation_node.ydata
        }]
      });

      mining_pending_transaction.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  mining_pending_transaction.ydata
        }]
      });
      proof_of_works.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  proof_of_works.ydata
        }]
      });
      full_transaction_validation.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  full_transaction_validation.ydata
        }]
      });

      contract_parsing.chart.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data:  contract_parsing.ydata
        }]
      });
    });

  }
}

Hooks.explorer_charts = {

  mounted() {
    var seconds_after_loading_of_this_graph = 0;
    var x_axis_data =  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var y_axis_data4 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    var chart4 = echarts.init(document.getElementById('explorer_charts_echartContainer'));
  
    var option4;
  
  
      option4= {
        grid: {
          left: '10%',
          right: '5%',
          bottom: '10%',
          top:"20%"
        },
        title: {
          left: 'center',
          text: 'Validation Time(ms)'
        },
        xAxis: {
          type: 'category',
          boundaryGap: false,
          data: x_axis_data,
          show:false,
          splitLine: {
            show: true,
            lineStyle:{color:"lightgrey",width:0.5}
          }
        },
        yAxis: {
          boundaryGap: [0, '50%'],
          type: 'value',
          splitLine: {
            show: true,
            lineStyle:{color:"lightgrey",width:0.5}
          },
          
        },
        series: [
          {
            type: 'line',
            symbol: 'none',
             itemStyle: {
              color: 'rgb(204, 0, 255,0.8)',
            },
            data: y_axis_data4
          }
        ]
      }; 
      option4 && chart4.setOption(option4);

      this.handleEvent("explorer_stats_points", ({ points }) => {
          console.log(points)
          seconds_after_loading_of_this_graph +=2;
          x_axis_data.shift();
          y_axis_data4.shift();
          x_axis_data.push(seconds_after_loading_of_this_graph);
          y_axis_data4.push(points.four);
          chart4.setOption({
            xAxis: {
              data: x_axis_data
            },
            series: [{
              name: 'data',
              data: y_axis_data4
            }]
          });
    
      });
  

  }

}

//adds 0 to the metric not recieved to avoid charts going blank
function structure_metric_points(latest_points){
  var points_default_value ={
    "archethic_election_validation_nodes_duration" : 0,
    "archethic_election_storage_nodes_duration" : 0,
    "archethic_mining_pending_transaction_validation_duration" : 0,
    "archethic_mining_proof_of_work_duration" : 0,
    "archethic_mining_full_transaction_validation_duration" : 0,
    "archethic_contract_parsing_duration" : 0,
    "archethic_mining_fetch_context_duration" : 0,
    "archethic_p2p_send_message_duration" : 0,
    "archethic_db_duration" : 0,
    "archethic_self_repair_duration" : 0,
    "vm_total_run_queue_lengths_io" : 0,
    "vm_total_run_queue_lengths_cpu" : 0,
    "vm_total_run_queue_lengths_total" : 0,
    "vm_system_counts_process_count" : 0,
    "vm_system_counts_port_count" : 0,
    "vm_system_counts_atom_count" : 0,
    "vm_memory_total" : 0,
    "vm_memory_system" : 0,
    "vm_memory_processes_used " : 0,
    "vm_memory_processes" : 0,
    "vm_memory_ets" : 0,
    "vm_memory_code" : 0,
    "vm_memory_binary" : 0,
    "vm_memory_atom_used" : 0,
    "vm_memory_atom" : 0
  };
  for (var key in latest_points) 
    points_default_value[key] = latest_points[key] 
  return  points_default_value;
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