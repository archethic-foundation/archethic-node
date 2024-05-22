import * as echarts from "echarts";

const TITLE_STYLE = {
  color: "white",
  fontSize: 14,
};
const AXIS_STYLE = {
  color: "white",
  fontSize: 14,
};
const COLOR_PALETTE = ["#CCA4FB"];

export function initBoxPlotTransactionsAvgDurationChart(el) {
  let chart = echarts.init(el);
  chart.setOption({
    color: COLOR_PALETTE,
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "15%",
    },
    title: {
      left: "center",
      text: "Average validation time",
      textStyle: TITLE_STYLE,
    },
    tooltip: {
      trigger: "axis",
    },
    xAxis: {
      type: "category",
      axisLabel: {
        textStyle: AXIS_STYLE,
      },
    },
    yAxis: {
      type: "value",
      axisLabel: {
        formatter: "{value} ms",
        textStyle: AXIS_STYLE,
      },
    },
    series: [
      {
        type: "boxplot",
        itemStyle: {
          color: COLOR_PALETTE[0],
        },
        tooltip: {
          valueFormatter: (value) => {
            if (value == 0) return "-";

            return Number.parseFloat(value).toFixed(1) + " ms";
          },
        },
      },
    ],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return chart;
}

export function initNetworkTransactionsCountChart(el) {
  let chart = echarts.init(el);
  chart.setOption({
    color: COLOR_PALETTE,
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "15%",
    },
    title: {
      left: "center",
      text: "Transactions count",
      textStyle: TITLE_STYLE,
    },
    tooltip: {
      trigger: "axis",
    },
    xAxis: {
      type: "category",
      axisLabel: {
        textStyle: AXIS_STYLE,
      },
    },
    yAxis: {
      type: "value",
      axisLabel: {
        textStyle: AXIS_STYLE,
      },
    },
    series: [
      {
        type: "line",
        areaStyle: {},
        data: [],
        smooth: 0.2,
        tooltip: {
          valueFormatter: (value) => {
            const plural = value > 1 ? "s" : "";
            return value + " transaction" + plural;
          },
        },
        showSymbol: false,
      },
    ],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return chart;
}

export function initNetworkTransactionsAvgDurationChart(el) {
  let chart = echarts.init(el);
  chart.setOption({
    color: COLOR_PALETTE,
    legend: {
      bottom: 0,
      type: "scroll",
    },
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "15%",
    },
    title: {
      left: "center",
      text: "Average validation time",
      textStyle: TITLE_STYLE,
    },
    tooltip: {
      trigger: "axis",
    },
    xAxis: {
      type: "category",
      axisLabel: {
        textStyle: AXIS_STYLE,
      },
    },
    yAxis: {
      type: "value",
      axisLabel: {
        formatter: "{value} ms",
        textStyle: AXIS_STYLE,
      },
    },
    series: [
      {
        type: "line",
        areaStyle: {},
        data: [],
        smooth: 0.2,
        showSymbol: false,
        tooltip: {
          valueFormatter: (value) => {
            if (value == 0) return "-";

            return Number.parseFloat(value).toFixed(1) + " ms";
          },
        },
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
    color: COLOR_PALETTE,
    legend: {
      bottom: 0,
      type: "scroll",
    },
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "15%",
    },
    title: {
      left: "center",
      text: "Transactions count by node (last 60min)",
      textStyle: TITLE_STYLE,
    },
    tooltip: {
      trigger: "axis",
    },
    xAxis: {
      show: false,
      type: "category",
    },
    yAxis: {
      type: "value",
      axisLabel: {
        textStyle: AXIS_STYLE,
      },
    },
    series: [
      {
        type: "bar",
        tooltip: {
          valueFormatter: (value) => {
            const plural = value > 1 ? "s" : "";
            return value + " transaction" + plural;
          },
        },
      },
    ],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return chart;
}

export function updateBoxPlotTransactionsAvgDurationChart(chart, stats) {
  chart.setOption({
    darkMode: true,
    xAxis: {
      data: Object.keys(stats).map(timestampToString),
    },
    series: [
      {
        data: Object.values(stats).map((durationsBucket) =>
          durationsBucket.map((duration) => duration / 1000000),
        ),
      },
    ],
  });
}

export function updateNetworkTransactionsCountChart(chart, stats) {
  chart.setOption({
    darkMode: true,
    xAxis: {
      data: Object.keys(stats).map(timestampToString),
    },
    series: [
      {
        data: Object.values(stats),
      },
    ],
  });
}

export function updateNetworkTransactionsAvgDurationChart(chart, stats) {
  chart.setOption({
    darkMode: true,
    xAxis: {
      data: Object.keys(stats).map(timestampToString),
    },
    series: [
      {
        data: Object.values(stats).map(
          (average_duration) => average_duration / 1_000_000,
        ),
      },
    ],
  });
}

export function updateNodeTransactionsCountChart(chart, stats) {
  chart.setOption({
    darkMode: true,
    xAxis: {
      data: Object.keys(stats).map(format_public_key),
    },
    series: [
      {
        data: Object.values(stats),
      },
    ],
  });
}

function timestampToString(timestamp) {
  return dateToString(new Date(timestamp * 1000));
}

function dateToString(date) {
  return (
    String(date.getUTCHours()).padStart(2, "0") +
    ":" +
    String(date.getUTCMinutes()).padStart(2, "0")
  );
}

function format_public_key(public_key) {
  // remove 3 chars, display 4, ..., display last 4
  return public_key.slice(3, 7) + "..." + public_key.slice(-4);
}
