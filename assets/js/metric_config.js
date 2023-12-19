import * as echarts from "echarts";

export function initNetworkTransactionsCountChart(el) {
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
      text: "Network transactions",
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

      axisLabel: {
        textStyle: {
          fontSize: 14,
        },
      },
    },
    series: [
      {
        type: "line",
        connectNulls: false,
        areaStyle: {},
        data: [],
        smooth: 0.2,
        tooltip: {
          valueFormatter: value => {
            const plural = value > 1 ? "s" : ""
            return value + ' transaction' + plural
          }
        },
        showSymbol: false
      },
    ],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return chart;
}

export function initNodeTransactionsCountChart(el) {
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
      text: "Nodes transactions",
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

      axisLabel: {
        textStyle: {
          fontSize: 14,
        },
      },
    },
    series: [],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return chart;
}
export function initNodeTransactionsAvgDurationChart(el) {
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
      text: "Nodes average validation time",
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
      axisLabel: {
        formatter: '{value} ms',
        textStyle: {
          fontSize: 14,
        },
      },
    },
    series: [],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return chart;
}

export function updateNetworkTransactionsCountChart(chart, stats) {
  chart.setOption({
    xAxis: {
      data: Object.keys(stats)
        .map((timestamp) => timestampToString(timestamp))
    },
    series: [{
      data: Object.values(stats)
    }],
  });
}

export function updateNodeTransactionsCountChart(chart, stats) {
  chart.setOption({
    series: Object.entries(stats)
      .map(([node_public_key, data]) => {
        let seriesData = [];
        for (let i = 0; i < data.timestamps.length; i++) {
          seriesData.push([
            timestampToString(data.timestamps[i]),
            data.counts[i]
          ]);
        }

        return {
          type: "line",
          connectNulls: false,
          name: format_public_key(node_public_key),
          smooth: 0.2,
          tooltip: {
            valueFormatter: value => {
              const plural = value > 1 ? "s" : ""
              return value + ' transaction' + plural
            }
          },
          showSymbol: false,
          data: seriesData
        };
      })
  });
}

export function updateNodeTransactionsAvgDurationChart(chart, stats) {
  chart.setOption({
    series: Object.entries(stats)
      .map(([node_public_key, data]) => {
        let seriesData = [];
        for (let i = 0; i < data.timestamps.length; i++) {
          seriesData.push([
            timestampToString(data.timestamps[i]),
            data.average_durations[i] / 1_000_000
          ]);
        }

        return {
          type: "line",
          connectNulls: false,
          name: format_public_key(node_public_key),
          smooth: 0.2,
          tooltip: {
            valueFormatter: value => {
              if (value == 0) return "-"

              return Number.parseFloat(value).toFixed(1) + ' ms'
            }
          },
          showSymbol: false,
          data: seriesData
        };
      })
  });
}

function timestampToString(timestamp) {
  return dateToString(new Date(timestamp * 1000));
}

function dateToString(date) {
  return String(date.getUTCHours()).padStart(2, '0') + ":" + String(date.getUTCMinutes()).padStart(2, '0');
}

function format_public_key(public_key) {
  // remove 3 chars, display 4, ..., display last 4
  return public_key.slice(3, 7) + "..." + public_key.slice(-4);
}