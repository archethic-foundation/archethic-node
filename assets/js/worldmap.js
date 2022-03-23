import * as echarts from 'echarts'
import worldmapJSON from '../static/worldmap.json'

let map

export function createWorldmap(worldmapDatas) {

  // calculate min and max number of nodes
  const temp = worldmapDatas.map(data => data.nb_of_nodes)

  const minNbOfNodes = Math.min(...temp)
  const maxNbOfNodes = Math.max(...temp)

  map = echarts.init(document.getElementById('worldmap'));

  echarts.registerMap('worldmap', {geoJSON: worldmapJSON})

  // Specify the configuration items and data for the chart
  const options = {
    tooltip:{},
    geo: {
      map: 'worldmap',
      id: 0,
      roam: true,
      zoom: 1.5,
      emphasis: {
        disabled: true,
      },
      scaleLimit: {
        min: 1,
        max: 20
      },
      itemStyle: {
        color : 'rgb(0,0,0,0.15)',
        borderColor: 'rgb(255,255,255)'
      },
      tooltip: {
        show: false
      }
    },
    series: [
      {
        name: 'nodes',
        type: 'custom',
        coordinateSystem: 'geo',
        geoIndex: 0,
        renderItem: renderItem,
        data: formatData(worldmapDatas),
        tooltip: {
          show: true,
          formatter: tooltipFormatter,
        }
      }
    ],
    visualMap: {
      type: 'continuous',
      min: minNbOfNodes,
      max: maxNbOfNodes,
      dimension: 4, /* Value to map (number of nodes) is in 5th position */
      textStyle: {
        color: 'white'
      },
      calculable: true,
      top: 0,
      bottom: 'auto'
    }
  };

  // Display the chart using the configuration items and data just specified.
  map.setOption(options);

  window.addEventListener('resize', map.resize)

}

// Format datas for echarts series
function formatData(datas) {
  return datas.map(data => [
    data.coords.lon[0],
    data.coords.lon[1],
    data.coords.lat[0],
    data.coords.lat[1],
    data.nb_of_nodes,
    data.geo_patch
  ])
}

function tooltipFormatter(params, ticket, callback) {
  const nbNodes = params.value[4]
  const geoPatch = params.value[5]
  let res = nbNodes.toString()
  res += nbNodes > 1 ? ' nodes' : ' node'
  res += '<br/>geo patch : ' + geoPatch
  return res
}

// Render a rectangle at coord and size of a geo patch
function renderItem(params, api) {
  const firstPoint = (api.coord([api.value(0), api.value(2)]))
  const secondPoint = (api.coord([api.value(1), api.value(3)]))
  const width = secondPoint[0] - firstPoint[0]
  const height = secondPoint[1] - firstPoint[1]

  // Offset is used to have better visual render
  const offset = 2

  // Color set by visualMap
  const color = api.visual('color')

  return {
    type: 'rect',
    shape: {
      x: firstPoint[0] + offset,
      y: firstPoint[1] + offset,
      width: width - offset,
      height: height + offset
    },
    style: {
      fill: color,
      opacity: 0.65,
      stroke: color === 'rgba(0,0,0,0)' ? color : 'rgb(0,0,0,0.5)',
      lineWidth: color === 'rgba(0,0,0,0)' ? 0 : 1
    }
  };
}

export function updateWorldmap(worldmapDatas) {
  // calculate new min and max number of nodes
  const temp = worldmapDatas.map(data => data.nb_of_nodes)

  const minNbOfNodes = Math.min(...temp)
  const maxNbOfNodes = Math.max(...temp)

  if (map) {
    map.setOption({
      series: [
        {
          name: 'nodes',
          data: formatData(worldmapDatas)
        }
      ],
      visualMap: {
        min: minNbOfNodes,
        max: maxNbOfNodes
      }
    })
  }
}