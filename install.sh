#!/bin/bash

# ==============================================================================
# 1. CONFIGURATION RÉSEAU ET VIRTUALISATION (Vagrant/VirtualBox)
# ==============================================================================

# Autoriser toutes les plages IP pour VirtualBox (évite les erreurs de restriction réseau)
cat << _EOF | sudo tee /etc/vbox/networks.conf > /dev/null
# Résolution des problèmes réseau potentiels (VBox)
* 0.0.0.0/0 ::/0
_EOF

# Installation du plugin pour gérer la taille des disques dans Vagrant
vagrant plugin install vagrant-disksize

# Lancement de l'infrastructure via Vagrant
vagrant up

# ==============================================================================
# 2. INSTALLATION DES OUTILS SYSTÈME ET CLI KUBERNETES
# ==============================================================================

# Mise à jour et installation des dépendances système
sudo apt update && sudo apt install -y curl bash-completion vim git

# Installation de kubectl (dernière version stable)
# K8S_RELEASE=$(curl -Ls https://dl.k8s.io/release/stable.txt)
K8S_RELEASE=v1.37.1
curl -LO "https://dl.k8s.io/release/${K8S_RELEASE}/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# Vérification de l'installation
kubectl version --client

# ==============================================================================
# 3. CONFIGURATION DU SHELL (Auto-complétion et Alias)
# ==============================================================================

# Ajout de l'auto-complétion et de l'alias 'k' dans le .bashrc
{
    echo 'source <(kubectl completion bash)'
    echo 'alias k=kubectl'
    echo 'complete -o default -F __start_kubectl k'
} >> ~/.bashrc

# Application immédiate des changements pour la session actuelle
source ~/.bashrc

# ==============================================================================
# 4. GESTION DES PAQUETS AVEC HELM
# ==============================================================================

# Téléchargement et installation de Helm 3
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh # Nettoyage du script d'installation

# ==============================================================================
# 5. CONFIGURATION DU CONTEXTE KUBERNETES (Kubeconfig)
# ==============================================================================

# Création du dossier de config et copie du fichier de configuration K8s
mkdir -p ~/.kube
cp ${PWD}/configs/config ~/.kube/config
chmod 600 ~/.kube/config

# Vérification de la connexion au cluster
kubectl get nodes -o wide

# ==============================================================================
# 6. VÉRIFICATION DE L'ÉTAT DU STOCKAGE (Longhorn)
# ==============================================================================

# Téléchargement de l'outil de diagnostic Longhorn (version AMD64 par défaut)
curl -sSfL -o longhornctl https://github.com/longhorn/cli/releases/download/v1.12.2/longhornctl-linux-amd64
chmod +x longhornctl

# Vérification des prérequis système pour Longhorn

export KUBECONFIG="$HOME/.kube/config"
./longhornctl check preflight

# ==============================================================================
# 7. ACCÈS À L'INTERFACE HEADLAMP (Dashboard)
# ==============================================================================

# Récupération automatique du nom du Pod Headlamp
export POD_NAME=$(kubectl get pods --namespace kube-system -l "app.kubernetes.io/name=headlamp,app.kubernetes.io/instance=my-headlamp" -o jsonpath="{.items[0].metadata.name}")

# Récupération du port du conteneur
export CONTAINER_PORT=$(kubectl get pod --namespace kube-system $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")

# Génération d'un jeton (token) pour se connecter à l'interface
echo "--- Token de connexion Headlamp ---"
kubectl create token my-headlamp --namespace kube-system

# Redirection de port pour accéder à l'interface sur http://localhost:8080
echo "Accès Headlamp disponible sur http://localhost:8080"
kubectl --namespace kube-system port-forward $POD_NAME 8080:$CONTAINER_PORT