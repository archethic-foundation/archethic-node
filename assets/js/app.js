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
  var y_axis_data = [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0, 0, 0, 0, 0, 0, 0, 0];
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
    var x_axis_data =  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    //1
    var archethic_election_validation_nodes_duration = generateEchartObjects('Election Duration-Validation Nodes','archethic_election_validation_nodes_duration',x_axis_data)
    //2
    var archethic_election_storage_nodes_duration = generateEchartObjects('Election Duration-Storage Nodes','archethic_election_storage_nodes_duration',x_axis_data)
    //3
    var archethic_mining_pending_transaction_validation_duration = generateEchartObjects('Mining Pending Transaction' , 'archethic_mining_pending_transaction_validation_duration',x_axis_data)
    //4
    var archethic_mining_proof_of_work_duration = generateEchartObjects( 'Duration(ms):Proof of Work ','archethic_mining_proof_of_work_duration',x_axis_data)
    //5
    var archethic_mining_full_transaction_validation_duration = generateEchartObjects('Full Transaction Validation','archethic_mining_full_transaction_validation_duration',x_axis_data)
    //6
    var archethic_contract_parsing_duration = generateEchartObjects('Duration: Contract Parsing','archethic_contract_parsing_duration',x_axis_data)
    //7
    var archethic_mining_fetch_context_duration = generateEchartObjects('Duration: mining_fetch_context','archethic_mining_fetch_context_duration',x_axis_data)
    //8
    var archethic_db_duration =  generateEchartObjects('Duration: archethic_db_duration','archethic_db_duration',x_axis_data)
 
    var archethic_p2p_send_message_duration,    archethic_self_repair_duration,    vm_total_run_queue_lengths_io,  vm_total_run_queue_lengths_cpu,    vm_total_run_queue_lengths_total,    vm_system_counts_process_count,
    vm_system_counts_port_count,    vm_system_counts_atom_count,    vm_memory_total,    vm_memory_system,
    vm_memory_processes_used ,    vm_memory_processes,    vm_memory_ets,    vm_memory_code,    vm_memory_binary,    vm_memory_atom_used,    vm_memory_atom;

    archethic_self_repair_duration = document.getElementById("archethic_self_repair_duration");
    vm_memory_processes  = document.getElementById("vm_memory_processes");
    vm_memory_ets  =  document.getElementById("vm_memory_ets");
    vm_memory_binary = document.getElementById("vm_memory_binary");

    vm_memory_system	 = document.getElementById("vm_memory_system");
    vm_memory_processes_used =	document.getElementById("vm_memory_processes_used ");
    // archethic_p2p_send_message_duration	 = document.getElementById("archethic_p2p_send_message_duration");

    vm_memory_total = document.getElementById("vm_memory_total");
    vm_system_counts_process_count = document.getElementById("vm_system_counts_process_count"); 

    vm_memory_atom = document.getElementById("vm_memory_atom");
    vm_total_run_queue_lengths_cpu = document.getElementById("vm_total_run_queue_lengths_cpu");

  	vm_system_counts_atom_count = document.getElementById("vm_system_counts_atom_count");
    vm_total_run_queue_lengths_total   = document.getElementById("vm_total_run_queue_lengths_total");
    
    vm_memory_atom_used = document.getElementById("vm_memory_atom_used");
  	vm_total_run_queue_lengths_io =  document.getElementById("vm_total_run_queue_lengths_io");
  	vm_system_counts_port_count = document.getElementById("vm_system_counts_port_count");
  	vm_memory_code = document.getElementById("vm_memory_code");


  


  
    this.handleEvent("node_points", ({
      points
    }) => {
     
      console.log(points);
      console.log("------------------")
      points = structure_metric_points(points)
      console.log("=================")
      console.log(points);
      console.log("=================")
      seconds_after_loading_of_this_graph+= 5;
      x_axis_data.push(++seconds_after_loading_of_this_graph);
      //1
      update_chart_data(archethic_election_validation_nodes_duration , x_axis_data ,points, "archethic_election_validation_nodes_duration" );
      //2
      update_chart_data( archethic_election_storage_nodes_duration , x_axis_data ,points, "archethic_election_storage_nodes_duration" );
      //3
      update_chart_data(archethic_mining_pending_transaction_validation_duration , x_axis_data ,points, "archethic_mining_pending_transaction_validation_duration" );
      //4
      update_chart_data( archethic_mining_proof_of_work_duration, x_axis_data ,points, "archethic_mining_proof_of_work_duration" );
      //5
      update_chart_data( archethic_mining_full_transaction_validation_duration , x_axis_data ,points, "archethic_mining_full_transaction_validation_duration" );
      //6
      update_chart_data(archethic_contract_parsing_duration , x_axis_data ,points, "archethic_contract_parsing_duration" )
      //7
      update_chart_data( archethic_mining_fetch_context_duration , x_axis_data ,points, "archethic_mining_fetch_context_duration" )
      //8
      update_chart_data(archethic_db_duration , x_axis_data ,points , "archethic_db_duration")

      //===============================
      update_card_data(archethic_self_repair_duration , points , "archethic_self_repair_duration");
      update_card_data(vm_memory_processes , points , "vm_memory_processes");
      update_card_data(vm_memory_ets , points , "vm_memory_ets");
      update_card_data(vm_memory_binary , points , "vm_memory_binary");
      update_card_data(vm_memory_system , points, "vm_memory_system" );
      update_card_data(vm_memory_processes_used  , points, "vm_memory_processes_used " );
      // update_card_data( archethic_p2p_send_message_duration , points, "archethic_p2p_send_message_duration" );
      update_card_data( vm_memory_total , points, "vm_memory_total" );
      update_card_data(vm_system_counts_process_count  , points, "vm_system_counts_process_count" );
      update_card_data( vm_memory_atom , points, "vm_memory_atom" );
      update_card_data( vm_total_run_queue_lengths_cpu , points, "vm_total_run_queue_lengths_cpu" );
      update_card_data( vm_system_counts_atom_count , points, "vm_system_counts_atom_count" );
      update_card_data( vm_total_run_queue_lengths_total , points, "vm_total_run_queue_lengths_total" );
      update_card_data( vm_memory_atom_used , points, "vm_memory_atom_used" );
      update_card_data( vm_total_run_queue_lengths_io , points, "vm_total_run_queue_lengths_io" );
      update_card_data( vm_system_counts_port_count , points, "vm_system_counts_port_count" );
      update_card_data( vm_system_counts_port_count , points, "vm_memory_code" );


    });

  }
}


function update_card_data(card_obj , points ,point_name ){
  card_obj.textContent = points[point_name]
}

function update_chart_data(chart_obj,x_axis_data ,points, point_name){
  chart_obj.ydata.push(points[point_name]);
  chart_obj.chart.setOption({
    xAxis: {
      data: x_axis_data
    },
    series: [{
      name: 'data',
      data: chart_obj.ydata
    }]
  });
}

Hooks.network_charts = {
  mounted() {
    var seconds_after_loading_of_this_graph = 0;
    var x_axis_data =  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    //1
    var archethic_election_validation_nodes_duration = generateEchartObjects('Election Duration-Validation Nodes','archethic_election_validation_nodes_duration',x_axis_data)
    //2
    var archethic_election_storage_nodes_duration = generateEchartObjects('Election Duration-Storage Nodes','archethic_election_storage_nodes_duration',x_axis_data)
    //3
    var archethic_mining_pending_transaction_validation_duration = generateEchartObjects('Mining Pending Transaction' , 'archethic_mining_pending_transaction_validation_duration',x_axis_data)
    //4
    var archethic_mining_proof_of_work_duration = generateEchartObjects( 'Duration(ms):Proof of Work ','archethic_mining_proof_of_work_duration',x_axis_data)
    //5
    var archethic_mining_full_transaction_validation_duration = generateEchartObjects('Full Transaction Validation','archethic_mining_full_transaction_validation_duration',x_axis_data)
    //6
    var archethic_contract_parsing_duration = generateEchartObjects('Duration: Contract Parsing','archethic_contract_parsing_duration',x_axis_data)
    //7
    var archethic_mining_fetch_context_duration = generateEchartObjects('Duration: mining_fetch_context','archethic_mining_fetch_context_duration',x_axis_data)
    //8
    var archethic_db_duration =  generateEchartObjects('Duration: archethic_db_duration','archethic_db_duration',x_axis_data)
    

    var p2pguage= echarts.init(document.getElementById('archethic_p2p_send_message_duration'));
    var p2pguage_options ={
      title: {
        left: 'center',
        text: `Duration:p2p_send_message(ms)`
      },
    series: [
      {
        
        type: 'gauge',
        center: ['50%', '60%'],
        startAngle: 200,
        endAngle: -20,
        min: 0,
        max: 1,
        splitNumber: 5,
        itemStyle: {
          color: '#00a4db'
        },
        progress: {
          show: true,
          width: 30
        },
        pointer: {
          show: false
        },
        axisLine: {
          lineStyle: {
            width: 30
          }
        },
        axisTick: {
          distance: -45,
          splitNumber: 5,
          lineStyle: {
            width: 2,
            color: '#cc00ff'
          }
        },
        splitLine: {
          distance: -52,
          length: 14,
          lineStyle: {
            width: 3,
            color: '#999'
          }
        },
        axisLabel: {
          distance: -20,
          color: '#999',
          fontSize: 20
        },
        anchor: {
          show: false
        },
        title: {
          show: false
        },
        detail: {
          valueAnimation: true,
          width: '60%',
          lineHeight: 40,
          borderRadius: 8,
          offsetCenter: [0, '-15%'],
          fontSize: 20,
          fontWeight: 'bolder',
          formatter: '{value} (ms)',
          color: 'auto'
        },
        data: [
          {
            value: 0
          }
        ]
      }    ]};

      p2pguage_options && p2pguage.setOption(p2pguage_options);


    var archethic_p2p_send_message_duration,    archethic_self_repair_duration,    vm_total_run_queue_lengths_io,  vm_total_run_queue_lengths_cpu,    vm_total_run_queue_lengths_total,    vm_system_counts_process_count,
    vm_system_counts_port_count,    vm_system_counts_atom_count,    vm_memory_total,    vm_memory_system,
    vm_memory_processes_used ,    vm_memory_processes,    vm_memory_ets,    vm_memory_code,    vm_memory_binary,    vm_memory_atom_used,    vm_memory_atom;

    archethic_self_repair_duration = document.getElementById("archethic_self_repair_duration");
    vm_memory_processes  = document.getElementById("vm_memory_processes");
    vm_memory_ets  =  document.getElementById("vm_memory_ets");
    vm_memory_binary = document.getElementById("vm_memory_binary");

    vm_memory_system	 = document.getElementById("vm_memory_system");
    vm_memory_processes_used =	document.getElementById("vm_memory_processes_used ");
    archethic_p2p_send_message_duration	 = document.getElementById("archethic_p2p_send_message_duration");

    vm_memory_total = document.getElementById("vm_memory_total");
    vm_system_counts_process_count = document.getElementById("vm_system_counts_process_count"); 

    vm_memory_atom = document.getElementById("vm_memory_atom");
    vm_total_run_queue_lengths_cpu = document.getElementById("vm_total_run_queue_lengths_cpu");

  	vm_system_counts_atom_count = document.getElementById("vm_system_counts_atom_count");
    vm_total_run_queue_lengths_total   = document.getElementById("vm_total_run_queue_lengths_total");
    
    vm_memory_atom_used = document.getElementById("vm_memory_atom_used");
  	vm_total_run_queue_lengths_io =  document.getElementById("vm_total_run_queue_lengths_io");
  	vm_system_counts_port_count = document.getElementById("vm_system_counts_port_count");
  	vm_memory_code = document.getElementById("vm_memory_code");


  
    this.handleEvent("network_points", ({
      points
    }) => {
      console.log("---------------")
      console.log(points);
      console.log("------------------")
      points = structure_metric_points(points)
      console.log("=================")
      console.log(points);
      console.log("=================")
      x_axis_data.push(++seconds_after_loading_of_this_graph);
      //1
      update_chart_data(archethic_election_validation_nodes_duration , x_axis_data ,points, "archethic_election_validation_nodes_duration" );
      //2
      update_chart_data( archethic_election_storage_nodes_duration , x_axis_data ,points, "archethic_election_storage_nodes_duration" );
      //3
      update_chart_data(archethic_mining_pending_transaction_validation_duration , x_axis_data ,points, "archethic_mining_pending_transaction_validation_duration" );
      //4
      update_chart_data( archethic_mining_proof_of_work_duration, x_axis_data ,points, "archethic_mining_proof_of_work_duration" );
      //5
      update_chart_data( archethic_mining_full_transaction_validation_duration , x_axis_data ,points, "archethic_mining_full_transaction_validation_duration" );
      //6
      update_chart_data(archethic_contract_parsing_duration , x_axis_data ,points, "archethic_contract_parsing_duration" )
      //7
      update_chart_data( archethic_mining_fetch_context_duration , x_axis_data ,points, "archethic_mining_fetch_context_duration" )
      //8
      update_chart_data(archethic_db_duration , x_axis_data ,points , "archethic_db_duration")

      //===============================
      update_card_data(archethic_self_repair_duration , points , "archethic_self_repair_duration");
      update_card_data(vm_memory_processes , points , "vm_memory_processes");
      update_card_data(vm_memory_ets , points , "vm_memory_ets");
      update_card_data(vm_memory_binary , points , "vm_memory_binary");
      update_card_data(vm_memory_system , points, "vm_memory_system" );
      update_card_data(vm_memory_processes_used  , points, "vm_memory_processes_used " );
      update_card_data( vm_memory_total , points, "vm_memory_total" );
      update_card_data(vm_system_counts_process_count  , points, "vm_system_counts_process_count" );
      update_card_data( vm_memory_atom , points, "vm_memory_atom" );
      update_card_data( vm_total_run_queue_lengths_cpu , points, "vm_total_run_queue_lengths_cpu" );
      update_card_data( vm_system_counts_atom_count , points, "vm_system_counts_atom_count" );
      update_card_data( vm_total_run_queue_lengths_total , points, "vm_total_run_queue_lengths_total" );
      update_card_data( vm_memory_atom_used , points, "vm_memory_atom_used" );
      update_card_data( vm_total_run_queue_lengths_io , points, "vm_total_run_queue_lengths_io" );
      update_card_data( vm_system_counts_port_count , points, "vm_system_counts_port_count" );
      update_card_data( vm_system_counts_port_count , points, "vm_memory_code" );

      p2pguage.setOption({  series: [  {    data: [     { value: points["archethic_p2p_send_message_duration"] }  ]    }      ]    });
      
    });

  }
}


Hooks.explorer_charts = {

  mounted() {
    var seconds_after_loading_of_this_graph = 0;
    var x_axis_data =  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var y_axis_data4 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    var archethic_mining_full_transaction_validation_duration = generateEchartObjects('Full Transaction Validation','archethic_mining_full_transaction_validation_duration',x_axis_data)
  
      this.handleEvent("explorer_stats_points", ({ points }) => {
        console.log(points);
        console.log("------------------")
        points = structure_metric_points(points)
        console.log("=================")
        console.log(points);
        console.log("=================")
        seconds_after_loading_of_this_graph+= 5;
        x_axis_data.push(++seconds_after_loading_of_this_graph);
        update_chart_data( archethic_mining_full_transaction_validation_duration , x_axis_data ,points, "archethic_mining_full_transaction_validation_duration" );

    
      });
  

  }

}

//adds 0 to the metric not recieved to avoid charts going blank
function structure_metric_points(latest_points){
  var points_default_value ={
    "archethic_archethic_election_validation_nodes_durations_duration" : 0,
    "archethic_election_storage_nodes_duration" : 0,
    "archethic_archethic_mining_pending_transaction_validation_duration_validation_duration" : 0,
    "archethic_mining_proof_of_work_duration" : 0,
    "archethic_mining_archethic_mining_full_transaction_validation_duration_duration" : 0,
    "archethic_archethic_contract_parsing_duration_duration" : 0,
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