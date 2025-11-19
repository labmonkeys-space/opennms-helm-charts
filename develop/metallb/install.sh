#!/usr/bin/env bash

helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install --create-namespace metallb metallb/metallb -n metallb-system
kubectl wait --for=condition=ready --timeout=90s -n metallb-system pod --selector=app.kubernetes.io/component=speaker
kubectl apply -f config.yaml -n metallb-system
