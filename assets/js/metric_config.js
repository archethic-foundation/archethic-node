import * as echarts from "echarts";

export function initializeNbTransactionGraph(el) {
  const xAxisData = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ];
  const yData = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  let chart = echarts.init(el);
  chart.setOption({
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "10%",
    },
    title: {
      left: "center",
      text: "Transaction volume",
      textStyle: {
        fontSize: 14,
      },
    },
    xAxis: {
      type: "category",
      data: xAxisData,
      show: false,
    },
    yAxis: {
      type: "value",
      boundaryGap: [0, "10%"],
      axisLabel: {
        textStyle: {
          fontSize: 14,
        },
      },
      splitLine: {
        show: true,
        lineStyle: { color: "lightgrey", width: 0.5 },
      },
    },
    series: [
      {
        type: "line",
        symbol: "none",
        triggerLineEvent: false,
        itemStyle: {
          color: "rgb(0, 164, 219,1)",
        },
        silent: true,
        data: yData,
      },
    ],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return { chart, xAxisData, yData, elapsedSeconds: 0 };
}

export function updateNbTransactionGraph(graph, nbTransactions) {
  graph.elapsedSeconds += 10;
  let shifted = graph.xAxisData.shift();
  graph.xAxisData.push(graph.elapsedSeconds);

  let new_data = 0,
    new_point = 0,
    shifted_value = 0;

  shifted_value = graph.yData.shift();
  graph.yData.push(nbTransactions);

  graph.chart.setOption({
    xAxis: {
      data: graph.xAxisData,
    },
    series: [
      {
        name: "data",
        data: graph.yData,
        smooth: 0.2,
      },
    ],
  });
}

export function initializeValidationDurationGraph(el) {
  const xAxisData = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ];
  const yData = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  let chart = echarts.init(el);
  chart.setOption({
    grid: {
      left: "10%",
      right: "5%",
      top: "15%",
      bottom: "10%",
    },
    title: {
      left: "center",
      text: "Transaction validation time",
      textStyle: {
        fontSize: 14,
      },
    },
    xAxis: {
      type: "category",
      data: xAxisData,
      show: false
    },
    yAxis: {
      type: "value",
      boundaryGap: [0, "10%"],
      axisLabel: {
        textStyle: {
          fontSize: 14,
        },
          formatter: "{value} ms"
      },
      splitLine: {
        show: true,
        lineStyle: { color: "lightgrey", width: 0.5 },
      },
    },
    series: [
      {
        type: "line",
        symbol: "none",
        triggerLineEvent: false,
        itemStyle: {
          color: "rgb(0, 164, 219,1)",
        },
        silent: true,
        data: yData,
      },
    ],
  });

  window.addEventListener("resize", function () {
    chart.resize();
  });

  return { chart, xAxisData, yData, elapsedSeconds: 0 };
}

export function updateValidationDurationGraph(graph, validationDuration) {
  graph.elapsedSeconds += 10;
  let shifted = graph.xAxisData.shift();
  graph.xAxisData.push(graph.elapsedSeconds);

  let new_data = 0,
    new_point = 0,
    shifted_value = 0;

  shifted_value = graph.yData.shift();
  graph.yData.push(validationDuration);

  graph.chart.setOption({
    xAxis: {
      data: graph.xAxisData,
    },
    series: [
      {
        name: "data",
        data: graph.yData,
        smooth: 0.2,
      },
    ],
  });
}
