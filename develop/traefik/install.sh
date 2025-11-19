#!/usr/bin/env bash

# Install Traefik
helm repo add traefik https://traefik.github.io/charts
helm repo update
kubectl create namespace traefik
helm upgrade --install --namespace traefik traefik traefik/traefik -f values.yaml
kubectl wait --for=condition=ready --timeout=90s -n traefik pod --selector=app.kubernetes.io/name=traefik
kubectl --namespace traefik apply -f gateway-http-8980.yaml
kubectl --namespace default apply -f route-http-8980.yaml
