import * as echarts from 'echarts';

//adds 0 to the metrics value, to avoid charts going blank
function structure_metric_points(latest_points) {

  var points_default_value = {
    "archethic_election_validation_nodes_duration": 0.0,
    "archethic_election_storage_nodes_duration": 0.0,
    "archethic_archethic_mining_pending_transaction_validation_duration": 0.0,
    "archethic_mining_proof_of_work_duration": 0.0,
    "archethic_mining_full_transaction_validation_duration": 0.0,
    "archethic_contract_parsing_duration": 0.0,
    "archethic_mining_fetch_context_duration": 0.0,
    "archethic_p2p_send_message_duration": 0.0,
    "archethic_db_duration": 0.0,
    "archethic_self_repair_duration": 0.0,
    "vm_total_run_queue_lengths_io": 0.0,
    "vm_total_run_queue_lengths_cpu": 0.0,
    "vm_total_run_queue_lengths_total": 0.0,
    "vm_system_counts_process_count": 0.0,
    "vm_system_counts_port_count": 0.0,
    "vm_system_counts_atom_count": 0.0,
    "vm_memory_total": 0.0,
    "vm_memory_system": 0.0,
    "vm_memory_processes_used": 0.0,
    "vm_memory_processes": 0.0,
    "vm_memory_ets": 0.0,
    "vm_memory_code": 0.0,
    "vm_memory_binary": 0.0,
    "vm_memory_atom_used": 0.0,
    "vm_memory_atom": 0.0
  };
  for (var key in latest_points)
    points_default_value[key] = latest_points[key]
  return points_default_value;
}

function get_visuals_dom() {
  var metric_object, x_axis_data = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  return metric_object = {
    seconds_after_loading_of_this_graph: 0,

    x_axis_data: x_axis_data,

    archethic_mining_proof_of_work_duration: generateEchartObjects(
      'PoW Duration(ms)', 'archethic_mining_proof_of_work_duration', x_axis_data),

    archethic_mining_full_transaction_validation_duration: generateEchartObjects(
      'Transaction Validation Duration(ms)',
      'archethic_mining_full_transaction_validation_duration', x_axis_data),

    tps: generate_echart_guage("Transactions Per Second(tps)", 'tps'),

    archethic_p2p_send_message_duration: generate_echart_guage(
      "P2P Message duration(ms) (Supervised Multicast)",
      'archethic_p2p_send_message_duration'),
  };
}

//echarts line_graph default  theme 
function line_graph_default_theme(heading, x_axis_data, y_axis_data) {

  return {
    //enforce default theme in theme echart(dom, "dark")
    backgroundColor: "#FFFFFF",
    grid: {
      left: '10%',
      right: '5%',
      bottom: '5%',
      top: "15%"
    },
    title: {
      left: 'center',
      text: ` ${heading}`,
      textStyle: {
        color: '#000000',
        fontSize: 16,
        fontFamily: "BlinkMacSystemFont,-apple-system,Segoe UI, Roboto, Oxygen, Ubuntu, Cantarell, Fira Sans, Droid Sans, Helvetica Neue,Helvetica, Arial, sans-serif"
      }
    },
    xAxis: {
      type: 'category',
      // boundaryGap: false,
      data: x_axis_data,
      show: false,
      splitLine: {
        show: true,
        lineStyle: { color: "lightgrey", width: 0.5 }
      }
    },
    yAxis: {
      boundaryGap: [0, '50%'],
      type: 'value',
      axisLabel: {
        formatter: '{value}',
        textStyle: {
          color: '#000000',
          fontSize: 16,
          fontFamily: "BlinkMacSystemFont,-apple-system,Segoe UI, Roboto, Oxygen, Ubuntu, Cantarell, Fira Sans, Droid Sans, Helvetica Neue,Helvetica, Arial, sans-serif"
        }
      },
      splitLine: {
        show: true,
        lineStyle: { color: "lightgrey", width: 0.5 }
      },
    },
    series: [{
      type: 'line',
      symbol: 'none',
      triggerLineEvent: false,
      itemStyle: {
        color: 'rgb(0, 164, 219,1)'
      },
      silent: true,
      data: y_axis_data,
    }]
  };
}

function generateEchartObjects(heading, echartContainer, x_axis_data) {
  var y_axis_data = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  var chart = echarts.init(document.getElementById(echartContainer));

  var option = line_graph_default_theme(heading, x_axis_data, y_axis_data);

  option && chart.setOption(option);
  window.addEventListener('resize', function () {
    chart.resize();
  });

  return { chart: chart, ydata: y_axis_data };
}

function guage_default_theme(heading) {

  return {
    //enforce default theme in theme echart(dom, "dark")
    backgroundColor: "#FFFFFF",
    title: {
      left: 'center',
      text: `${heading}`,
      textStyle: {
        color: '#000000',
        fontSize: 16,
        fontFamily: "BlinkMacSystemFont,-apple-system,Segoe UI, Roboto, Oxygen, Ubuntu, Cantarell, Fira Sans, Droid Sans, Helvetica Neue,Helvetica, Arial, sans-serif"
      }
    },
    series: [{

      type: 'gauge',
      center: ['50%', '74%'],
      startAngle: 200,
      endAngle: -20,
      min: 0,
      max: 0,
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
          color: '#000000'
        }
      },
      splitLine: {
        distance: -52,
        length: 14,
        lineStyle: {
          width: 3,
          color: '#000000'
        }
      },
      axisLabel: {
        distance: -20,
        color: '#000000 ',
        fontSize: 16,
        formatter: function (value) {
          return exponent_formatter(value);
        }
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
        fontSize: 16,
        fontWeight: 'bolder',
        formatter: function (value) {
          return exponent_formatter(value);
        },
        color: 'inherit'
      },
      data: [{
        value: 0
      }]
    }]
  }
}

function generate_echart_guage(heading, eguageContainer) {
  var guage = echarts.init(document.getElementById(eguageContainer));

  var guage_options = guage_default_theme(heading)

  guage_options && guage.setOption(guage_options);
  window.addEventListener('resize', function () {
    guage.resize();
  });

  return { "guage": guage, "max": 0 }
}

// for proper display of axis labels
function exponent_formatter(new_point) {
  if (new_point == 0) return 0
  else if (new_point > 100000 || new_point < 0.0001) return parseFloat(new_point).toExponential(2);
  else if (new_point < 100000 && new_point >= 100) return Math.floor(parseFloat(new_point));
  else if (new_point < 100 && new_point >= 0.0001) return parseFloat(new_point).toPrecision(2);
}

//update the charts with new data
function update_chart_data(chart_obj, x_axis_data, points, point_name) {
  var new_data = 0,
    new_point = 0,
    shifted_value = 0;

  new_point = points[point_name];
  new_data = chart_obj.ydata[chart_obj.ydata.length - 1] + new_point;

  shifted_value = chart_obj.ydata.shift();
  chart_obj.ydata.push(new_data);

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

// update the guage with new data
function update_guage_data(guage_obj, points, point_name) {
  var new_data = 0,
    new_point = 0;

  new_point = points[point_name];
  new_data = new_point;
  if (new_data >= guage_obj.max) {
    guage_obj.max = new_data
  }

  guage_obj.guage.setOption({
    series: [{
      min: 0,
      max: guage_obj.max,
      splitNumber: 5,
      data: [{ value: new_data }]
    }]
  });
}

function create_network_live_visuals() {
  var metric_obj = get_visuals_dom();
  return metric_obj;
}

function update_network_live_visuals(network_metric_obj, points) {
  // points = metric_config.structure_metric_points(points)
  return update_live_visuals(network_metric_obj, points)
}

function update_live_visuals(metric_obj, points) {

  metric_obj.seconds_after_loading_of_this_graph += 10;
  var shifted = metric_obj.x_axis_data.shift();
  metric_obj.x_axis_data.push(metric_obj.seconds_after_loading_of_this_graph);

  update_chart_data(metric_obj.archethic_mining_proof_of_work_duration, metric_obj.x_axis_data, points, "archethic_mining_proof_of_work_duration");
  update_chart_data(metric_obj.archethic_mining_full_transaction_validation_duration, metric_obj.x_axis_data, points, "archethic_mining_full_transaction_validation_duration");

  update_guage_data(metric_obj.archethic_p2p_send_message_duration, points, "archethic_p2p_send_message_duration");
  update_guage_data(metric_obj.tps, points, "tps");

  return metric_obj;
}

function create_explorer_live_visuals() {
  var obj, x_axis_data;
  x_axis_data = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  obj = {
    seconds_after_loading_of_this_graph: 0,
    x_axis_data: x_axis_data,

    archethic_mining_full_transaction_validation_duration:

      generateEchartObjects('Transaction Validation duration (ms)',
        'archethic_mining_full_transaction_validation_duration', x_axis_data)
  };
  return obj;
};

function update_explorer_live_visuals(explorer_metric_obj, points) {
  // points = metric_config.structure_metric_points(points)
  //passing objects's variable through by reference
  explorer_metric_obj.seconds_after_loading_of_this_graph += 5;
  var shifted = explorer_metric_obj.x_axis_data.shift();

  explorer_metric_obj.x_axis_data.push(explorer_metric_obj.seconds_after_loading_of_this_graph);
  update_chart_data(explorer_metric_obj.archethic_mining_full_transaction_validation_duration,
    explorer_metric_obj.x_axis_data, points, "archethic_mining_full_transaction_validation_duration");

  return explorer_metric_obj;
};

export {
  create_network_live_visuals,
  update_network_live_visuals,
  create_explorer_live_visuals,
  update_explorer_live_visuals,
  structure_metric_points
};
