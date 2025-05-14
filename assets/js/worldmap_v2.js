import L from 'leaflet';
import 'leaflet.markercluster';
import 'leaflet.markercluster/dist/MarkerCluster.css';
import 'leaflet.markercluster/dist/MarkerCluster.Default.css';
import './leaflet.curve';

let map


function shortAddress(addressBytes) {
  // Convert bytes to hex string
  const hex = Array.from(addressBytes)
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");

  const short = `${hex.slice(0, 8)}...${hex.slice(-4)}`;

  // Create elements
  const span = document.createElement("span");
  span.className = "mono";
  span.style = "color:black;"

  span.setAttribute("data-tooltip", hex);

  // Hidden full hex span
  const fullSpan = document.createElement("span");
  fullSpan.style = "color:black;"
  fullSpan.textContent = hex;
  fullSpan.style.display = "none";

  // Assemble final span
  span.appendChild(fullSpan);
  span.appendChild(document.createTextNode(short + " "));

  return span.outerHTML;
}




function formatData(datas, authorized) {
  return datas
    .map(data => {
      return {
        "id": 1,
        "name": data.first_public_key,
        "ip": data.ip,
        "port": data.port,
        "lat": data.lat,
        "lng": data.lng,
        "city": data.city,
        "country": data.country,
        "average_availability": data.average_availability,
        "authorized": data.authorized,
        "global_availability": data.global_availability,
        "local_availability": data.local_availability 
      }
    })
}


function formatPopupBody(node) {

 

  const color_global_availability = node.global_availability  ? "green" : "red";
  const color_local_availability = node.local_availability  ? "green" : "red";
  const color_authorised = node.authorized ? "green" : "red";

  const status =  node.global_availability && node.local_availability && node.authorized;
  const color = status  ? "green" : "red";

  let body = "<div style='color:black;min-width:250px'>";
  body += `<h1 style='width:100%;text-align: center;display:block;font-weight:bold;color:black;Line-height: 20px;font-size:20px'>${shortAddress(node.name)}</h1>`;
  body += `<hr style="border: none; border-top: 2px solid #666; margin: 8px 0;"></hr>`;
  body += `<p style='color:black;Line-height: 8px'><span style="display: inline-block; width: 10px; height: 10px; border-radius: 50%; background-color: ${color_authorised};margin-right:5px;"></span>   Authorized</p>`;
  body += `<p style='color:black;Line-height: 8px'><span style="display: inline-block; width: 10px; height: 10px; border-radius: 50%; background-color: ${color_global_availability};margin-right:5px;"></span>   Global availability</p>`;
  body += `<p style='color:black;Line-height: 8px'><span style="display: inline-block; width: 10px; height: 10px; border-radius: 50%; background-color: ${color_local_availability};margin-right:5px;"></span>   Local availability</p>`;
   body += `<p style="color:black;Line-height: 10px">Availability : <strong>${node.average_availability}</strong></p>`;
  body += `<hr style="border: none; border-top: 2px solid #666; margin: 8px 0;"></hr>`;
  body += `<p style="color:black;Line-height: 10px">Location: <strong>${node.city}, ${node.country}</strong></p>`;
  body += `<p style="color:black;Line-height: 10px">ip : <strong>${node.ip}</strong></p>`;
  body += `<hr style="border: none; border-top: 2px solid #666; margin: 8px 0;"></hr>`;
  body += `<a style="width:100%;text-align: center;display:block;font-weight:bold;margin-top:15px;font-size:16px" href="/explorer/node/${node.name}" target="_blank"><span style=" width:100%;color:blue;margin-top:15px; cursor: pointer">View Details</span></a>`;
  body += "</div>"

  return body
}


export function createWorldmap(worldmapDatas) {
 
  map = L.map('map').setView([20, 0], 2);
  if (!window.map) {
    window.map = map;
  }


  L.tileLayer('https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; CARTO',
    subdomains: 'abcd',
    maxZoom: 19
  }).addTo(map);

  const markers = L.markerClusterGroup({
    iconCreateFunction: function (cluster) {
      const children = cluster.getAllChildMarkers();
      const total = children.length;
      const upCount = children.filter(m => m.options.status  ).length;
      const downCount = total - upCount;
      const upPercent = (upCount / total) * 100;
      const downPercent = 100 - upPercent;
      const radius = 18;
      const strokeWidth = 8;
      const circumference = 2 * Math.PI * radius;
      const upDash = (upPercent / 100) * circumference;
      const downDash = (downPercent / 100) * circumference;

      const svg = `
        <svg width="60" height="60" viewBox="0 0 60 60">
          <title>${upCount} UP / ${downCount} DOWN</title>
          <circle cx="30" cy="30" r="${radius + strokeWidth / 2}" fill="white" />
          <circle cx="30" cy="30" r="${radius}" fill="none" stroke="red"
            stroke-width="${strokeWidth}" stroke-dasharray="${downDash} ${circumference}"
            transform="rotate(-90 30 30)" />
          <circle cx="30" cy="30" r="${radius}" fill="none" stroke="lime"
            stroke-width="${strokeWidth}" stroke-dasharray="${upDash} ${circumference}"
            transform="rotate(${(360 * downPercent / 100 - 90)} 30 30)" />
          <text x="50%" y="50%" text-anchor="middle" dominant-baseline="central"
            font-size="14" fill="#000" font-weight="bold">${total}</text>
        </svg>
      `;

      return L.divIcon({
        html: svg,
        className: 'custom-cluster-icon',
        iconSize: [60, 60]
      });
    }
  });

  const nodes = formatData(worldmapDatas, true);
     console.log(nodes);
  nodes.forEach(node => {
     const status =  node.global_availability && node.local_availability && node.authorized;
    
    const icon = L.divIcon({
      className: status ? 'marker-up' : 'marker-down',
      iconSize: [20, 20]
    });
    if ((node.lat != null) && (node.lng != null)) {
      const marker = L.marker([node.lat, node.lng], {
        icon,
        status: status
      }).bindPopup(formatPopupBody(node));
      markers.addLayer(marker);
    }
  });

  map.addLayer(markers);

  window.addEventListener('resize', map.resize)
}


export function updateWorldmap(worldmapDatas) {

  if (map) {
    console.log("updateWorldmap");
    const nodes = formatData(worldmapDatas, true); 
    console.log(nodes);
    nodes.forEach(node => {
       const status =  node.global_availability && node.local_availability && node.authorized;
    
      const icon = L.divIcon({
        className: status ? 'marker-up' : 'marker-down',
        iconSize: [20, 20]
      });

      if ((node.lat != null) && (node.lng != null)) {
        const marker = L.marker([node.lat, node.lng], {
          icon,
          status:status
        }).bindPopup(formatPopupBody(node));
        markers.addLayer(marker);
      }

    });
 
  }
}
