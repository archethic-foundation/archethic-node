// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import {} from "../css/app.scss"
import {} from './ui'

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured

import {
  Socket
} from "phoenix"
import LiveSocket from "phoenix_live_view"
import {
  html
} from "diff2html"
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
  page() {
    return this.el.dataset.page
  },
  mounted() {
    this.pending = this.page()
    window.addEventListener("scroll", e => {
      if (this.pending == this.page() && scrollAt() > 90) {
        this.pending = this.page() + 1
        this.pushEvent("load-more", {})
      }

    })
  },
  reconnected() {
    this.pending = this.page()
  },
  updated() {
    this.pending = this.page()
  }
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

Hooks.echart1 = {
  mounted() {
    var seconds_after_loading_of_this_graph = 0;
    var x_axis_data =  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var y_axis_data1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var y_axis_data2 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var y_axis_data3 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var y_axis_data4 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    var chart1 = echarts.init(document.getElementById('echartContainer1'));
    var chart2 = echarts.init(document.getElementById('echartContainer2'));
    var chart3 = echarts.init(document.getElementById('echartContainer3'));
    var chart4 = echarts.init(document.getElementById('echartContainer4'));

    var option1,option2,option3,option4;

    option1 = {
      xAxis: {
        type: 'category',
        boundaryGap: false,
        show: false,
        data: x_axis_data,
        splitLine: {
          show: true,
          lineStyle: {
            width: 0.5,
            color: "white"
          }
        }
      },
      yAxis: {
        boundaryGap: [0, '50%'],
        type: 'value',
        splitLine: {
          show: true,
          lineStyle: {
            width: 0.5,
            color: "white"
          }
        }
      },
      series: [{
        name: 'values',
        type: 'line',
        smooth: true,
        symbol: 'none',
        stack: 'a',
        areaStyle: {
          opacity: 0.8,
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [{
              offset: 0,
              color: 'rgba(255, 0, 135)'
            },
            {
              offset: 1,
              color: 'rgba(135, 0, 157)'
            }
          ])
        },
        data: y_axis_data1
      }]
    };
  
    option2= {
      xAxis: {
        type: 'category',
        boundaryGap: false,
        show: false,
        data: x_axis_data,
        splitLine: {
          show: true,
          lineStyle: {
            width: 0.5,
            color: "white"
          }
        }
      },
      yAxis: {
        boundaryGap: [0, '50%'],
        type: 'value',
        splitLine: {
          show: true,
          lineStyle: {
            width: 0.5,
            color: "white"
          }
        }
      },
      series: [{
        name: 'values',
        type: 'line',
        smooth: true,
        symbol: 'none',
        stack: 'a',
        areaStyle: {
          opacity: 0.8,
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            {
              offset: 0,
              color: 'rgba(255, 191, 0)'
            },
            {
              offset: 1,
              color: 'rgba(224, 62, 76)'
            }
          ])
        },
        data: y_axis_data2
      }]
    };
  

    option3 = {
      xAxis: {
        type: 'category',
        boundaryGap: false,
        show: false,
        data: x_axis_data,
        splitLine: {
          show: true,
          lineStyle: {
            width: 0.5,
            color: "white"
          }
        }
      },
      yAxis: {
        boundaryGap: [0, '50%'],
        type: 'value'
      },
      series: [{
        name: 'values',
        type: 'line',
        smooth: true,
        symbol: 'none',
        stack: 'a',
        areaStyle: {
          opacity: 0.8,
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [{
              offset: 0,
              color: 'rgba(128, 255, 165)'
            },
            {
              offset: 1,
              color: 'rgba(1, 191, 236)'
            }
          ])
        },
        data: y_axis_data3
      }]
    };

    option4 = {
      xAxis: {
        type: 'time',
        splitLine: {
          show: true,
          lineStyle :{color:"black",width:0.5}
        },
      },
      yAxis: {
        type: 'value',
        axisTick: {
          inside: true
        },
        splitLine: {
          show: true,
          lineStyle :{color:"black",width:0.5}
        },
        axisLabel: {
          inside: true,
          formatter: '{value}\n'
        },
        z: 10
      },
      grid: {
        top: 110,
        left: 15,
        right: 15,
        height: 160
      },
      dataZoom: [
        {
          type: 'inside',
          throttle: 50
        }
      ],
      series: [
    
        {
          name: 'Fake Data',
          type: 'line',
          smooth: true,
          stack: 'a',
          symbol: 'circle',
          symbolSize: 5,
          sampling: 'average',
          itemStyle: {
            color: '#F2597F'
          },
          areaStyle: {
            color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
              {
                offset: 0,
                color: 'rgba(213,72,120,0.8)'
              },
              {
                offset: 1,
                color: 'rgba(213,72,120,0.3)'
              }
            ])
          },
          data: y_axis_data4
        }
      ]
    };    



    option1 && chart1.setOption(option1);
    option2 && chart2.setOption(option2);
    option3 && chart3.setOption(option3);
    option4 && chart4.setOption(option4);

    this.handleEvent("points", ({
      points
    }) => {
      seconds_after_loading_of_this_graph++;
      console.log(x_axis_data.shift(),y_axis_data1.shift(),y_axis_data2.shift(),y_axis_data3.shift(),y_axis_data4.shift());
      x_axis_data.push(seconds_after_loading_of_this_graph);
      y_axis_data1.push(points[0]);
      y_axis_data2.push(points[0]);
      y_axis_data3.push(points[1]);
      y_axis_data4.push(points[1]);
      chart1.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data: y_axis_data1
        }]
      });

      chart2.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data: y_axis_data2
        }]
      });


      chart3.setOption({
        xAxis: {
          data: x_axis_data
        },
        series: [{
          name: 'data',
          data: y_axis_data3
        }]
      });

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










let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: {
    _csrf_token: csrfToken
  },
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