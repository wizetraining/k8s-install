#!/bin/bash
#
# Deploys the Kubernetes dashboard when enabled in settings.yaml

set -euxo pipefail

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# first add our custom repo to your local helm repositories
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/

# now you should be able to install headlamp via helm
helm install my-headlamp headlamp/headlamp --namespace kube-system

## Installation Longhorn

helm repo add longhorn https://charts.longhorn.io

# Fetch the latest charts from the repository:

helm repo update

# Install Longhorn in the longhorn-system namespace.

helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version 1.12.2

# To confirm that the deployment succeeded, run:

kubectl -n longhorn-system get pod

# 1. Ajout et mise à jour du repo
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# 2. Installation avec --set
helm upgrade --install metallb metallb/metallb \
  --create-namespace \
  --namespace metallb-system \
  --set "controller.tolerations[0].key=node-role.kubernetes.io/control-plane" \
  --set "controller.tolerations[0].operator=Exists" \
  --set "controller.tolerations[0].effect=NoSchedule" \
  --set "controller.tolerations[1].key=node-role.kubernetes.io/master" \
  --set "controller.tolerations[1].operator=Exists" \
  --set "controller.tolerations[1].effect=NoSchedule" \
  --set "speaker.tolerations[0].key=node-role.kubernetes.io/control-plane" \
  --set "speaker.tolerations[0].operator=Exists" \
  --set "speaker.tolerations[0].effect=NoSchedule" \
  --set "speaker.tolerations[1].key=node-role.kubernetes.io/master" \
  --set "speaker.tolerations[1].operator=Exists" \
  --set "speaker.tolerations[1].effect=NoSchedule"


# Attendre que les CRDs soient prêts avant d'appliquer la config
kubectl rollout status deployment -n metallb-system metallb-controller --timeout=90s

# Appliquer la configuration IP

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: vagrant-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.56.200-192.168.56.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: vagrant-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - vagrant-pool
EOF

