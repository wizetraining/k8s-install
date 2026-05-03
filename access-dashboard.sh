#!/bin/bash

# Récupération automatique du nom du Pod Headlamp
export POD_NAME=$(kubectl get pods --namespace kube-system -l "app.kubernetes.io/name=headlamp,app.kubernetes.io/instance=my-headlamp" -o jsonpath="{.items[0].metadata.name}")

# Récupération du port du conteneur
export CONTAINER_PORT=$(kubectl get pod --namespace kube-system $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")

# Génération d'un jeton (token) pour se connecter à l'interface
echo "--- Token de connexion au Dashboard Kubernetes à Copier ---"
echo ""
kubectl create token my-headlamp --namespace kube-system
echo ""

# Redirection de port pour accéder à l'interface sur http://localhost:8080
echo "Accès au Dashboard Kubernetes sur http://localhost:8080"
echo ""
echo "Ne fermez pas ce terminal !!!!"
echo ""

kubectl --namespace kube-system port-forward $POD_NAME 8080:$CONTAINER_PORT

