#!/bin/bash
echo 'Port Forwarding via Miniupnpc'
echo 'Installing Miniupnpc'
# sudo apt-get install miniupnpc
echo 'Loooking for Upnp IGD Device'

log_folder=~/aebot/aen_network_logs
mkdir -p $log_folder
echo $log_folder

log_nb=`date`
touch $log_folder/"$log_nb"
upnpc -l &>> $log_folder/"$log_nb"

if  grep -i -q "NO IGD UPnP" $log_folder/"$log_nb"
then
    echo "No UPnP IGD Device Found on the network 
         Re-Run this script after enabling UPnP on CME router and CGNAT.
         OR Contact your ISP for manual port forwarding"
    echo "Halting..."
    exit 0
fi
     local_ip=$( grep "Local" $log_folder/"$log_nb"  |  cut -d " " -f 6) 
    external_ip=$( grep "ExternalIPAddress" $log_folder/"$log_nb" | cut -d " " -f 3) 

    echo 
    echo local_ip: $local_ip  external_ip: $external_ip
    echo 
    # get default ports
    [[ -z "${ARCHETHIC_HTTP_PORT}" ]] && http_port=40000 || http_port="${ARCHETHIC_HTTP_PORT}"
    [[ -z "${ARCHETHIC_P2P_PORT}" ]] && p2p_port=30002 || p2p_port="${ARCHETHIC_P2P_PORT}"

    upnpc -d  $http_port tcp &>> $log_folder/"$log_nb"
    upnpc -d  $p2p_port tcp &>> $log_folder/"$log_nb"
    upnpc -e "ARCHETHIC_HTTP_PORT_$http_port" -a $local_ip $http_port $http_port tcp  &>> $log_folder/"$log_nb"
    upnpc -e "ARCHETHIC_P2P_PORT_$p2p_port"   -a $local_ip $p2p_port  $p2p_port  tcp  &>> $log_folder/"$log_nb"

    grep "0 TCP" $log_folder/"$log_nb"
    echo
    grep "1 TCP" $log_folder/"$log_nb"