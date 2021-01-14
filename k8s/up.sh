#!/usr/bin/env bash

export PATH=$PWD:$PATH

# Metrics

kubectl apply -f 1.0-uniris-metrics-namespace.yaml
kubectl apply -f 1.1-prometheus-config.yaml
kubectl apply -f 1.2-prometheus-services.yaml
kubectl apply -f 1.3-prometheus.yaml

# Result

echo ''
eval printf '=%.0s' {1..$(tput cols)}
echo ''
echo ''
echo "IP: $(minikube ip)"
echo ''
echo 'Telemetry:'
echo "Prometheus: $(minikube ip):$(kubectl -n uniris-metrics get service prometheus-svc -o jsonpath='{.spec.ports[?(@.name=="tcp-prometheus")].nodePort}')"