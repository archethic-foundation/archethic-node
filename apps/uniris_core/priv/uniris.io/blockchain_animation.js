
(function() {

    var svg = d3.select("#blockchain-anim")
      .append("svg")
      .style("display", "block")
      .style("margin", "auto")
      .attr("viewBox", "-1400 0 3000 650")
  
      var startedBlockchainAnim = false
      document.addEventListener("scroll", function() {
        if (isScrolledIntoView(document.querySelector("#blockchain-anim"))) {
          if (startedBlockchainAnim) {
              return
          }
          generateWorld()
          startedBlockchainAnim = true
        }
      })
  
  
      function isScrolledIntoView(el) {
        var rect = el.getBoundingClientRect();
        var elemTop = rect.top;
        var elemBottom = rect.bottom;
      
        // Only completely visible elements return true:
        var isVisible = (elemTop >= 0) && (elemBottom <= window.innerHeight);
        // Partially visible elements return true:
        //isVisible = elemTop < window.innerHeight && elemBottom >= 0;
        return isVisible;
      }
  
      function generateWorld() {
  
          var width = 300, height = 300;
        
          var proj = d3.geo.orthographic()
              .translate([width / 2, height / 2])
              .clipAngle(90)
              .scale(300);  
              
          proj.rotate([0,-30,0])
        
          var sky = d3.geo.orthographic()
              .translate([width / 2, height / 2])
              .clipAngle(90)
              .scale(300);
  
          var path = d3.geo.path().projection(proj).pointRadius(3);
          
          var swoosh = d3.svg.line()
              .x(function(d) { return d[0] })
              .y(function(d) { return d[1] })
              .interpolate("cardinal")
              .tension(.0);
        
          var g = svg
            .append("g")
            .attr("opacity", 0)
            .attr("transform", "translate(0,200)")
          
          /******************
          * Load map and cities
          ********************/
          places = [
          {
              "name": "Los Angeles",
              "coordinates": [
                  -118.181926369940413,
                  33.991924108765431
              ]
          },
          {
              "name": "Moscow",
              "coordinates": [
                  37.613576967271399,
                  55.754109981248178
              ]
          },
          { 
              "name": "Mexico City",
              "coordinates": [
                  -99.132934060293906,
                  19.444388301415472
              ]
          },
          {
              "name": "Lagos",
              "coordinates": [
                  3.389585212598433,
                  6.445207512093191
              ]
          },
          {
              "name": "Kolkata",
              "coordinates": [
                  88.32272979950551,
                  22.496915156896421
              ]
          },
          {
              "name": "Washington, D.C.",
              "coordinates": [
                  -77.011364439437159,
                  38.901495235087054
              ]
          },
          {
              "name": "Casablanca",
              "coordinates": [ 
                  -7.618313291698712, 
                  33.601922074258482
              ]
          },
          {
              "name": "Paris",
              "coordinates": [
                  2.33138946713035, 
                  48.868638789814611
              ]
          },
          {
              "name": "Cap Town",
              "coordinates": [
                  18.433042299226031, 
                  -33.918065108628753
              ]
          },
          {
              "name": "Madrid",
              "coordinates": [
                  -3.685297544612524, 
                  40.401972123113808 
              ]
          },
          {
              "name": "Rio Janero",
              "coordinates": [
                  -43.226966652843657, 
                  -22.923077315615956
              ]
          },
          {
              "name": "Cairo",
              "coordinates": [
                  31.248022361126118, 
                  30.051906205103705
              ]
          }
          ]

          queue()
            .defer(d3.json, "https://blockchain.uniris.io/api/last_transaction/0052568AC0E83BFF82629B0B7F8CB7570CBDF566739C935840C53AEF74D852167A/content?mime=application/json")
            .await(function(err, world) {
              
                /**************
                 * Create earth lands
                 ***************/
                g.append("path")
                    .datum(topojson.object(world, world.objects.land))
                    .attr("class", "land noclicks")
                    .attr("d", path)
                    .attr("fill", "#000")
                    .attr("fill-opacity", "0.2")
                    .attr("stroke", "#fff")
        
        
                /**************
                 * Create and animate links between cities
                 ***************/
                g.transition()
                .duration(1000)
                .delay(1500)
                .attr("opacity", 1)
                .each("end", function() {
                  
                  var onBlockchainSection = false
                  document.addEventListener("scroll", function() {
                    if (isScrolledIntoView(document.querySelector("#blockchain-anim"))) {
                      if (onBlockchainSection) {
                        return
                      }
                      onBlockchainSection = true
                      displayLines(true)
                    } else {
                      onBlockchainSection = false
                    }
                  })
  
                  displayLines()
  
                  function displayLines(loop) {
                    var it = 0
  
                    if (loop) {
                      d3.selectAll("#blockchain-anim .flyer").each(function() {
                        this.remove()
                      })
                    }
  
                    for (var i = 0; i < Math.floor(places.length / 3); i++) {
                      var rand1 = Math.floor(Math.random() * places.length)
                      
                      while (rand1 == i && distanceCoord(places[i].coordinates[1], places[i].coordinates[0], places[rand1].coordinates[1], places[rand1].coordinates[0], "K") < 1000) {
                        rand1 = Math.floor(Math.random() * places.length)
                      }
  
                      var rand2 = Math.floor(Math.random() * places.length)
                      while (rand2 == i && rand2 == rand1 && distanceCoord(places[i].coordinates[1], places[i].coordinates[0], places[rand2].coordinates[1], places[rand2].coordinates[0], "K") < 1000) {
                        rand2 = Math.floor(Math.random() * places.length)
                      }
  
                      var rand3 = Math.floor(Math.random() * places.length)
                      while (rand3 == i && rand3 == rand2 && rand3 == rand1 && distanceCoord(places[i].coordinates[1], places[i].coordinates[0], places[rand3].coordinates[1], places[rand3].coordinates[0], "K") < 1000) {
                        rand3 = Math.floor(Math.random() * places.length)
                      }
  
                      drawLine(places[i], places[rand1], i)
                      drawLine(places[i], places[rand2], i)
                      drawLine(places[i], places[rand3], i)
                    }
  
                    function drawLine(from, to, i) {
                      arc = {
                        source: from.coordinates,
                        target: to.coordinates
                      }
                      var arcLine = g.append("path")
                        .attr("class", "flyer")
                        .attr("stroke", "#00a4db")
                        .attr("stroke-width", "3")
                        .attr("fill", "none")
                        .attr("opacity", "0.5")
                        .attr("d", function(d) { return swoosh(flying_arc(proj, sky, arc)) })
    
                      var totalLength = arcLine.node().getTotalLength();
                      arcLine
                          .attr("stroke-dasharray", totalLength + " " + totalLength)
                          .attr("stroke-dashoffset", totalLength)
                          .transition()
                          .duration(1000)
                          .delay(i*1000)
                          .attr("stroke-dashoffset", 0)
                          .each("end", function() {
                            it++
                            if (it == places.length && onBlockchainSection) {
                              displayLines(true)
                            }
                          })
                    }
                  }
                })
            });
  
            function flying_arc(proj, sky, pts) {
              var source = pts.source,
                  target = pts.target;
            
              var mid = location_along_arc(source, target, .5);
              var result = [ proj(source),
                              sky(mid),
                              proj(target) ]
              return result;
            }
            
            function location_along_arc(start, end, loc) {
              var interpolator = d3.geo.interpolate(start,end);
              return interpolator(loc)
            }
        }
        
  
        function distanceCoord(lat1, lon1, lat2, lon2, unit) {
          if ((lat1 == lat2) && (lon1 == lon2)) {
            return 0;
          }
          else {
            var radlat1 = Math.PI * lat1/180;
            var radlat2 = Math.PI * lat2/180;
            var theta = lon1-lon2;
            var radtheta = Math.PI * theta/180;
            var dist = Math.sin(radlat1) * Math.sin(radlat2) + Math.cos(radlat1) * Math.cos(radlat2) * Math.cos(radtheta);
            if (dist > 1) {
              dist = 1;
            }
            dist = Math.acos(dist);
            dist = dist * 180/Math.PI;
            dist = dist * 60 * 1.1515;
            if (unit=="K") { dist = dist * 1.609344 }
            if (unit=="N") { dist = dist * 0.8684 }
            return dist;
          }
        }
  })()