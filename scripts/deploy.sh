#!/bin/bash
set -e

echo "▶ Установка Ingress-nginx и Cert-manager..."
kubectl apply -f k3s/ingress-nginx.yaml
kubectl apply -f k3s/cert-manager.yaml

echo "▶ Ожидание готовности..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=120s
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=120s

echo "▶ Деплой PigeonGram..."
kubectl apply -k k3s/

echo "▶ Статус:"
kubectl get pods -n pigeongram
kubectl get ingress -n pigeongram