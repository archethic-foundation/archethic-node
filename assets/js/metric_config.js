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
      text: "Transaction volume",
      textStyle: {
        color: 'white',
        fontSize: 14,
      },
    },
    tooltip: {
      trigger: 'axis'
    },
    xAxis: {
      type: "category",
      axisLabel: {
        textStyle: {
          color: 'white',
          fontSize: 14,
        },
      },
    },
    yAxis: {
      type: "value",
      boundaryGap: [0, "10%"],
      axisLabel: {
        textStyle: {
          color: 'white',
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

export function updateNbTransactionGraph(graph, nbTransactions) {
  if (graph.xData.length >= 10) {
    graph.xData.shift()
  }
  graph.xData.push(new Date().toLocaleString().replace(' ', '\n'))

  if (graph.yData.length >= 10) {
    graph.yData.shift()
  }
  graph.yData.push(nbTransactions)

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
      text: "Transaction validation time",
      textStyle: {
        color: 'white',
        fontSize: 14,
      },
    },
    tooltip: {
      trigger: 'axis'
    },
    xAxis: {
      type: "category",
      axisLabel: {
        textStyle: {
          color: 'white',
          fontSize: 14,
        },
      },
    },
    yAxis: {
      type: "value",
      boundaryGap: [0, "10%"],
      axisLabel: {
        textStyle: {
          color: 'white',
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

export function updateValidationDurationGraph(graph, validationDuration) {
  if (graph.xData.length >= 10) {
    graph.xData.shift()
  }
  graph.xData.push(new Date().toLocaleString().replace(' ', '\n'))

  if (graph.yData.length >= 10) {
    graph.yData.shift()
  }
  graph.yData.push(validationDuration)

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
