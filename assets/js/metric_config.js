import * as echarts from "echarts";

const pollInterval = 5

export function initializeNbTransactionGraph(el) {
  let chart = echarts.init(el);
  chart.setOption({
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "15%",
    },
    title: {
      left: "center",
      text: "Validations count (successful or not)",
      textStyle: {
        fontSize: 14,
      },
    },
    tooltip: {
      trigger: 'axis'
    },
    xAxis: {
      type: "category"
    },
    yAxis: {
      type: "value",
      boundaryGap: [0, "10%"],
      axisLabel: {
        textStyle: {
          fontSize: 14,
        },
      },
    },
    series: [
      {
        type: "line",
        areaStyle: {},
        data: [],
        smooth: 0.2,
        showSymbol: false
      },
    ],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return { chart, xData: [], yData: [] };
}

export function updateNbTransactionGraph(graph, stats) {
  graph.xData = Object.keys(stats)
    .sort()
    .map((timestamp) => timestampToString(timestamp))

  graph.yData = Object.values(stats)
    .map((durations) => durations.length)

  graph.chart.setOption({
    xAxis: {
      data: graph.xData,
    },
    series: [
      {
        data: graph.yData
      },
    ],
  });
}

export function initializeValidationDurationGraph(el) {
  let chart = echarts.init(el);

  chart.setOption({
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "15%",
    },
    title: {
      left: "center",
      text: "Average transaction validation time",
      textStyle: {
        fontSize: 14,
      },
    },
    tooltip: {
      trigger: 'axis'
    },
    xAxis: {
      type: "category"
    },
    yAxis: {
      type: "value",
      boundaryGap: [0, "10%"],
      axisLabel: {
        formatter: '{value} ms',
        textStyle: {
          fontSize: 14,
        },
      },
    },
    series: [
      {
        type: "line",
        areaStyle: {},
        data: [],
        smooth: 0.2,
        showSymbol: false
      },
    ],
  });
  window.addEventListener("resize", function () {
    chart.resize();
  });

  return { chart, xData: [], yData: [] };
}

export function updateValidationDurationGraph(graph, stats) {
  graph.xData = Object.keys(stats)
    .sort()
    .map((timestamp) => timestampToString(timestamp))

  graph.yData = Object.values(stats)
    .map((durations) => {
      return Math.floor(durations.reduce((acc, duration) => acc + duration, 0) / durations.length / 1_000_000)
    })

  graph.chart.setOption({
    xAxis: {
      data: graph.xData,
    },
    series: [
      {
        data: graph.yData
      },
    ],
  });
}

export function initializeNodeChart(el) {
  let chart = echarts.init(el);

  chart.setOption({
    legend: {
      bottom: 0,
      type: 'scroll',
    },
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "15%",
    },
    title: {
      left: "center",
      text: "Average transaction validation time per node",
      textStyle: {
        fontSize: 14,
      },
    },
    tooltip: {
      trigger: 'axis'
    },
    xAxis: {
      type: "category"
    },
    yAxis: {
      type: "value",
      boundaryGap: [0, "10%"],
      axisLabel: {
        formatter: '{value} ms',
        textStyle: {
          fontSize: 14,
        },
      },
    },
    series: [
    ],
  });
  window.addEventListener("resize", function () {
    chart.resize();
  });

  return { chart, xData: [], yData: [] };
}

export function updateNodeChart(graph, stats) {
  const timestamps = Object.values(stats)
    .map((data) => data.timestamps)
    .flat()
    .sort()

  const uniqueTimestamps = Array.from(new Set(timestamps))
    .map((timestamp) => timestampToString(timestamp))

  graph.chart.setOption({
    xAxis: {
      data: uniqueTimestamps
    },
    series: Object.entries(stats)
      .map(([node_public_key, data]) => {

        let seriesData = []
        for (let i = 0; i < data.timestamps.length; i++) {
          seriesData.push([
            data.timestamps[i],
            Math.floor(data.durations[i].reduce((acc, duration) => acc + duration, 0) / data.durations.length / 1_000_000)
          ])
        }

        // we sort before it's a string to handle the 23:59 < 0:00
        seriesData.sort((a, b) => a[0] > b[0])

        seriesData = seriesData.map(([timestamp, value]) => [timestampToString(timestamp), value])

        return {
          type: "line",
          name: format_public_key(node_public_key),
          smooth: 0.2,
          showSymbol: false,
          data: seriesData
        }
      })
  });
}

function timestampToString(timestamp) {
  return dateToString(new Date(timestamp * 1000))
}

function dateToString(date) {
  return String(date.getUTCHours()).padStart(2, '0') + ":" + String(date.getUTCMinutes()).padStart(2, '0')
}

function format_public_key(public_key) {
  // remove 3 chars, display 4, ..., display last 4
  return public_key.slice(3, 7) + "..." + public_key.slice(-4)
}