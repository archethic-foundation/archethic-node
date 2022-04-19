import * as echarts from 'echarts'
import worldmapJSON from '../static/worldmap.json'

let map
let minNbOfNodes
let maxNbOfNodes

export function createWorldmap(worldmapDatas) {
  // calculate min and max number of nodes
  const temp = worldmapDatas.map(data => data.nb_of_nodes)

  minNbOfNodes = Math.min(...temp)
  maxNbOfNodes = Math.max(...temp)

  map = echarts.init(document.getElementById('worldmap'));

  echarts.registerMap('worldmap', {geoJSON: worldmapJSON})

  // Specify the configuration items and data for the chart
  const options = {
    tooltip:{},
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
    data.geo_patch,
    minNbOfNodes,
    maxNbOfNodes
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
      (0.8 * (nbNodes - min) / (max - min)) + 0.2 : 1
    
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
  // calculate new min and max number of nodes
  const temp = worldmapDatas.map(data => data.nb_of_nodes)

  minNbOfNodes = Math.min(...temp)
  maxNbOfNodes = Math.max(...temp)

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