  import * as echarts from  './echarts.min.js';
  
  //adds 0 to the metric not recieved to avoid charts going blank
  function structure_metric_points(latest_points){
    var points_default_value ={
      "archethic_archethic_election_validation_nodes_durations_duration" : 0.0,
      "archethic_election_storage_nodes_duration" : 0.0,
      "archethic_archethic_mining_pending_transaction_validation_duration_validation_duration" : 0.0,
      "archethic_mining_proof_of_work_duration" : 0.0,
      "archethic_mining_archethic_mining_full_transaction_validation_duration_duration" : 0.0,
      "archethic_archethic_contract_parsing_duration_duration" : 0.0,
      "archethic_mining_fetch_context_duration" : 0.0,
      "archethic_p2p_send_message_duration" : 0.0,
      "archethic_db_duration" : 0.0,
      "archethic_self_repair_duration" : 0.0,
      "vm_total_run_queue_lengths_io" : 0.0,
      "vm_total_run_queue_lengths_cpu" : 0.0,
      "vm_total_run_queue_lengths_total" : 0.0,
      "vm_system_counts_process_count" : 0.0,
      "vm_system_counts_port_count" : 0.0,
      "vm_system_counts_atom_count" : 0.0,
      "vm_memory_total" : 0.0,
      "vm_memory_system" : 0.0,
      "vm_memory_processes_used" : 0.0,
      "vm_memory_processes" : 0.0,
      "vm_memory_ets" : 0.0,
      "vm_memory_code" : 0.0,
      "vm_memory_binary" : 0.0,
      "vm_memory_atom_used" : 0.0,
      "vm_memory_atom" : 0.0
    };
    for (var key in latest_points) 
      points_default_value[key] = latest_points[key] 
    return  points_default_value;
  }

function get_visuals_dom(){
  var metric_object , x_axis_data;
  x_axis_data = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];


  return    metric_object = {
    seconds_after_loading_of_this_graph: 0,
    x_axis_data: x_axis_data ,
  //1
   archethic_election_validation_nodes_duration:   generateEchartObjects('Election Duration-Validation Nodes','archethic_election_validation_nodes_duration',x_axis_data),
  //2
   archethic_election_storage_nodes_duration:   generateEchartObjects('Election Duration-Storage Nodes','archethic_election_storage_nodes_duration',x_axis_data),
  //3
   archethic_mining_pending_transaction_validation_duration:   generateEchartObjects('Mining Pending Transaction' , 'archethic_mining_pending_transaction_validation_duration',x_axis_data),
  //4
   archethic_mining_proof_of_work_duration:   generateEchartObjects( 'Duration(ms):Proof of Work ','archethic_mining_proof_of_work_duration',x_axis_data),
  //5
   archethic_mining_full_transaction_validation_duration:   generateEchartObjects('Full Transaction Validation','archethic_mining_full_transaction_validation_duration',x_axis_data),
  //6
   archethic_contract_parsing_duration:   generateEchartObjects('Duration: Contract Parsing','archethic_contract_parsing_duration',x_axis_data),
  //7
   archethic_mining_fetch_context_duration:   generateEchartObjects('Duration: mining_fetch_context','archethic_mining_fetch_context_duration',x_axis_data),
  //8
  archethic_db_duration:    generateEchartObjects('Duration: archethic_db_duration','archethic_db_duration',x_axis_data),


  //9 cards
  archethic_self_repair_duration:   document.getElementById("archethic_self_repair_duration"),
  //10
  vm_memory_processes:   document.getElementById("vm_memory_processes"),
  //11
  vm_memory_ets:    document.getElementById("vm_memory_ets"),
  //12
  vm_memory_binary:   document.getElementById("vm_memory_binary"),
  //13
  vm_memory_system	:   document.getElementById("vm_memory_system"),
  //14
  vm_memory_processes_used:  	document.getElementById("vm_memory_processes_used"),


  //15
  vm_memory_total:   document.getElementById("vm_memory_total"),
  //16
  vm_system_counts_process_count:   document.getElementById("vm_system_counts_process_count"), 
  //17
  vm_memory_atom:   document.getElementById("vm_memory_atom"),
  //18
  vm_total_run_queue_lengths_cpu:   document.getElementById("vm_total_run_queue_lengths_cpu"),
  //19
  vm_system_counts_atom_count:   document.getElementById("vm_system_counts_atom_count"),
  //20
  vm_total_run_queue_lengths_total:   document.getElementById("vm_total_run_queue_lengths_total"),
  //21
  vm_memory_atom_used:   document.getElementById("vm_memory_atom_used"),
  //22
  vm_total_run_queue_lengths_io:    document.getElementById("vm_total_run_queue_lengths_io"),
  //23
  vm_system_counts_port_count:   document.getElementById("vm_system_counts_port_count"),
  //24
  vm_memory_code:   document.getElementById("vm_memory_code"),

  archethic_p2p_send_message_duration : generate_echart_guage("archethic_p2p_send_message_duration", 'archethic_p2p_send_message_duration')



  };
}

  function generateEchartObjects(heading , echartContainer ,  x_axis_data){
    var y_axis_data = 
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
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

 
  function generate_echart_guage(heading , eguageContainer  ){
    var guage= echarts.init(document.getElementById(eguageContainer));
  
    var guage_options ={
      title: {
        left: 'center',
        text: `${heading}(ms)`
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
  
     guage_options && guage.setOption(guage_options);
  
  
    return guage
  }
  

function update_chart_data(chart_obj,x_axis_data ,points, point_name){
  var shifted =     chart_obj.ydata.shift();
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

function update_card_data(card_obj , points ,point_name ){
    card_obj.textContent = points[point_name]
  }
  
function update_guage_data(guage_obj , points , point_name )
{
  guage_obj.setOption({series: [{data: [{ value: points[point_name] }]}]});
}


function create_node_live_visuals(){
      var  metric_obj = get_visuals_dom();
    return metric_obj;
}

function update_node_live_visuals(node_metric_obj , points){
      // points = metric_config.structure_metric_points(points)
  return update_live_visuals(node_metric_obj , points);
}

function create_network_live_visuals(){
 var metric_obj = get_visuals_dom();
    return metric_obj;
}

function update_network_live_visuals(network_metric_obj , points){
  // points = metric_config.structure_metric_points(points)
  return update_live_visuals(network_metric_obj , points)
}

function update_live_visuals(metric_obj , points){
  metric_obj.seconds_after_loading_of_this_graph+= 5;
  var shifted = metric_obj.x_axis_data.shift();
  metric_obj.x_axis_data.push(metric_obj.seconds_after_loading_of_this_graph);
  //1
  update_chart_data(metric_obj.archethic_election_validation_nodes_duration , metric_obj.x_axis_data ,points, "archethic_election_validation_nodes_duration" );
  //2
  update_chart_data( metric_obj.archethic_election_storage_nodes_duration , metric_obj.x_axis_data , points , "archethic_election_storage_nodes_duration" );
  //3
  update_chart_data(metric_obj.archethic_mining_pending_transaction_validation_duration , metric_obj.x_axis_data , points, "archethic_mining_pending_transaction_validation_duration" );
  //4
  update_chart_data(metric_obj.archethic_mining_proof_of_work_duration, metric_obj.x_axis_data ,points, "archethic_mining_proof_of_work_duration" );
  //5
  update_chart_data( metric_obj.archethic_mining_full_transaction_validation_duration , metric_obj.x_axis_data ,points, "archethic_mining_full_transaction_validation_duration" );
  //6
  update_chart_data(metric_obj.archethic_contract_parsing_duration , metric_obj.x_axis_data ,points, "archethic_contract_parsing_duration" )
  //7
  update_chart_data( metric_obj.archethic_mining_fetch_context_duration , metric_obj.x_axis_data ,points, "archethic_mining_fetch_context_duration" )
  //8
  update_chart_data(metric_obj.archethic_db_duration , metric_obj.x_axis_data ,points , "archethic_db_duration")

  //===============================card
  //9
  update_card_data(metric_obj.archethic_self_repair_duration , points , "archethic_self_repair_duration");
  //10
  update_card_data(metric_obj.vm_memory_processes , points , "vm_memory_processes");
  //11
  update_card_data(metric_obj.vm_memory_ets , points , "vm_memory_ets");
  //12
  update_card_data(metric_obj.vm_memory_binary , points , "vm_memory_binary");
  //13
  update_card_data(metric_obj.vm_memory_system , points, "vm_memory_system" );
  //14
  update_card_data(metric_obj.vm_memory_processes_used  , points, "vm_memory_processes_used" );
  //15
  update_card_data( metric_obj.vm_memory_total , points, "vm_memory_total" );
  //16
  update_card_data(metric_obj.vm_system_counts_process_count  , points, "vm_system_counts_process_count" );
  //17
  update_card_data( metric_obj.vm_memory_atom , points, "vm_memory_atom" );
  //18
  update_card_data( metric_obj.vm_total_run_queue_lengths_cpu , points, "vm_total_run_queue_lengths_cpu" );
  //19
  update_card_data( metric_obj.vm_system_counts_atom_count , points, "vm_system_counts_atom_count" );
  //20
  update_card_data( metric_obj.vm_total_run_queue_lengths_total , points, "vm_total_run_queue_lengths_total" );
  //21
  update_card_data( metric_obj.vm_memory_atom_used , points, "vm_memory_atom_used" );
  //22
  update_card_data( metric_obj.vm_total_run_queue_lengths_io , points, "vm_total_run_queue_lengths_io" );
  //23
  update_card_data( metric_obj.vm_system_counts_port_count , points, "vm_system_counts_port_count" );
  //24
  update_card_data( metric_obj.vm_system_counts_port_count , points, "vm_memory_code" );
  //25
  update_guage_data( metric_obj.archethic_p2p_send_message_duration , points, "archethic_p2p_send_message_duration" );

    return metric_obj;
}

function create_explorer_live_visuals(){
  var obj , x_axis_data;
  x_axis_data = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
   obj =  {  
     seconds_after_loading_of_this_graph: 0,
     x_axis_data:  x_axis_data,
     archethic_mining_full_transaction_validation_duration: generateEchartObjects('Full Transaction Validation','archethic_mining_full_transaction_validation_duration',x_axis_data) 
      };
    return obj;
};

function update_explorer_live_visuals(explorer_metric_obj, points){
    // points = metric_config.structure_metric_points(points)
     //passing objects's variable through by reference
    explorer_metric_obj.seconds_after_loading_of_this_graph+= 5;
    var shifted = explorer_metric_obj.x_axis_data.shift();
    explorer_metric_obj.x_axis_data.push(explorer_metric_obj.seconds_after_loading_of_this_graph);

    update_chart_data(explorer_metric_obj.archethic_mining_full_transaction_validation_duration , 
      explorer_metric_obj.x_axis_data ,points, "archethic_mining_full_transaction_validation_duration" );

      return explorer_metric_obj; 
};

  export  {
    create_node_live_visuals ,  
    update_node_live_visuals ,
    create_network_live_visuals ,
    update_network_live_visuals , 
    create_explorer_live_visuals , 
    update_explorer_live_visuals, 
    structure_metric_points}  ;

