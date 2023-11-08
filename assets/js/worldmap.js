import * as echarts from 'echarts'
import worldmapJSON from './worldmap.json'

let map
let minNbOfAuthorizedNodes
let maxNbOfAuthorizedNodes
let minNbOfPendingNodes
let maxNbOfPendingNodes

export function createWorldmap(worldmapDatas) {

  calculateNbOfNodes(worldmapDatas)

  map = echarts.init(document.getElementById('worldmap'));

  echarts.registerMap('worldmap', { geoJSON: worldmapJSON })

  // Specify the configuration items and data for the chart
  const options = {
    tooltip: {},
    legend: {
      selectedMode: 'single',
      textStyle: {
        color: 'white',
        fontSize: 16
      }
    },
    geo: {
      map: 'worldmap',
      // Using Equirectangular projection
      projection: {
        project: (point) => [point[0], point[1] * -1],
        unproject: (point) => [point[0], point[1] * -1]
      },
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
        color: 'rgb(0,0,0,0.15)',
        borderColor: 'rgb(255,255,255)'
      },
      tooltip: {
        show: false
      }
    },
    series: [
      {
        name: 'authorized nodes',
        id: 0,
        type: 'custom',
        coordinateSystem: 'geo',
        geoIndex: 0,
        renderItem: renderItem,
        data: formatData(worldmapDatas, true),
        label: {
          show: true,
          color: 'white',
        },
        tooltip: {
          show: true,
          formatter: tooltipFormatter,
        }
      },
      {
        name: 'pending nodes',
        id: 1,
        type: 'custom',
        coordinateSystem: 'geo',
        geoIndex: 0,
        renderItem: renderItem,
        data: formatData(worldmapDatas, false),
        label: {
          show: true,
          color: 'white',
        },
        tooltip: {
          show: true,
          formatter: tooltipFormatter,
        }
      }
    ],
    visualMap: [
      {
        show: false,
        type: 'continuous',
        min: minNbOfAuthorizedNodes,
        max: maxNbOfAuthorizedNodes,
        dimension: 4, /* Value to map (number of nodes) is in 5th position */
        seriesIndex: 0 /* Authorized nodes */
      },
      {
        show: false,
        type: 'continuous',
        min: minNbOfPendingNodes,
        max: maxNbOfPendingNodes,
        dimension: 4, /* Value to map (number of nodes) is in 5th position */
        seriesIndex: 1 /* Pending nodes */
      }
    ]
  };

  // Display the chart using the configuration items and data just specified.
  map.setOption(options);

  window.addEventListener('resize', map.resize)
}

// Calculate min and max number of nodes
function calculateNbOfNodes(datas) {
  const authorizedNodes = datas.filter(data => data.authorized)
    .map(data => data.nb_of_nodes)

  minNbOfAuthorizedNodes = Math.min(...authorizedNodes)
  maxNbOfAuthorizedNodes = Math.max(...authorizedNodes)

  const pendingNodes = datas.filter(data => !data.authorized)
    .map(data => data.nb_of_nodes)

  minNbOfPendingNodes = Math.min(...pendingNodes)
  maxNbOfPendingNodes = Math.max(...pendingNodes)
}

// Format datas for echarts series
function formatData(datas, authorized) {
  return datas.filter(data => data.authorized === authorized)
    .map(data => {
      return data.authorized === authorized ?
        [
          data.coords.lon[0],
          data.coords.lon[1],
          data.coords.lat[0],
          data.coords.lat[1],
          data.nb_of_nodes,
          data.geo_patch,
          authorized ? minNbOfAuthorizedNodes : minNbOfPendingNodes,
          authorized ? maxNbOfAuthorizedNodes : maxNbOfPendingNodes
        ] : null
    })
}

function tooltipFormatter(params, ticket, callback) {
  const nbNodes = params.value[4]
  const geoPatch = params.value[5]
  let res = nbNodes.toString()
  res += nbNodes > 1 ? ' nodes' : ' node'
  res += '<br/>geo patch : ' + geoPatch
  return res
}

// Render a circle and a emphasis rectangle at coord of a geo patch
function renderItem(params, api) {
  // Color set by visualMap
  const color = api.visual('color')
  // return value only if color is set by visualMap
  if (color != 'rgba(0,0,0,0)') {
    const firstPoint = api.coord([api.value(0), api.value(2)])
    const secondPoint = api.coord([api.value(1), api.value(3)])

    // Circle
    const centerPoint = [
      (firstPoint[0] + secondPoint[0]) / 2,
      (firstPoint[1] + secondPoint[1]) / 2
    ]

    const maxRadius = Math.abs((secondPoint[0] - firstPoint[0]) / 2)

    // Calculate radius to have a range from 20% to 100% of maxRadius
    const min = api.value(6)
    const max = api.value(7)
    const nbNodes = api.value(4)

    // Avoid dividing by 0
    const percent = max !== min ?
      (0.60 * (nbNodes - min) / (max - min)) + 0.40 : 1

    const radius = maxRadius * percent

    // Rectangle
    const rectWidth = secondPoint[0] - firstPoint[0]
    const rectHeight = secondPoint[1] - firstPoint[1]

    return {
      type: 'group',
      children: [
        {
          type: 'circle',
          shape: {
            cx: centerPoint[0],
            cy: centerPoint[1],
            r: radius
          },
          style: {
            fill: color,
            opacity: 0.65,
            stroke: 'rgb(0,0,0,0.5)',
            lineWidth: 1
          }
        },
        // rectangle to show geo patch square on emphasis
        {
          type: 'rect',
          shape: {
            x: firstPoint[0],
            y: firstPoint[1],
            width: rectWidth,
            height: rectHeight
          },
          style: {
            fill: 'rgba(0,0,0,0)',
            opacity: 0
          },
          emphasis: {
            style: {
              opacity: 1,
              stroke: 'rgb(0,0,0,0.5)',
              lineWidth: 1
            }
          }
        }
      ]
    };
  } else {
    return null
  }
}

export function updateWorldmap(worldmapDatas) {
  calculateNbOfNodes(worldmapDatas)

  if (map) {
    map.setOption({
      series: [
        {
          name: 'authorized nodes',
          data: formatData(worldmapDatas, true)
        },
        {
          name: 'pending nodes',
          data: formatData(worldmapDatas, false)
        }
      ],
      visualMap: [
        {
          min: minNbOfAuthorizedNodes,
          max: maxNbOfAuthorizedNodes
        },
        {
          min: minNbOfPendingNodes,
          max: maxNbOfPendingNodes
        }
      ]
    })
  }
}