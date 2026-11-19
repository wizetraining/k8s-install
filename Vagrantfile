# -*- mode: ruby -*-
# vi: set ft=ruby :

# --- CONFIGURATION DES VARIABLES ---
CLUSTER_NAME = "Kubernetes Cluster"
BOX = "bento/ubuntu-24.04"
K8S_VERSION = "1.37.1-00"
OS_VERSION  = "xUbuntu_24.04"

CONTROL_IP  = "192.168.56.10"
POD_CIDR    = "172.16.1.0/16"
SVC_CIDR    = "172.17.1.0/18"
DNS_SERVERS = "8.8.8.8 1.1.1.1"

WORKER_COUNT = 3
VM_CPUS      = 4
VM_MEMORY    = 4096

Vagrant.configure("2") do |config|
  
  # Détection automatique de l'architecture (Apple Silicon vs Intel/AMD)
  arch = `uname -m`.strip == "aarch64" ? "-arm64" : ""
  config.vm.box = "#{BOX}#{arch}"

  # Extension du disque principal (nécessite le plugin vagrant-disksize)
  config.disksize.size = '70GB'

  # --- PROVISIONING COMMUN (HOSTS FILE) ---
  config.vm.provision "shell", inline: <<-SHELL
    apt-get update -y
    echo "#{CONTROL_IP} master-node" >> /etc/hosts
    for i in $(seq 1 #{WORKER_COUNT}); do
      echo "192.168.56.$((10+i)) worker-node0${i}" >> /etc/hosts
    done
  SHELL

  # FONCTION POUR ÉVITER LA RÉPÉTITION (Provider & Disque secondaire)
  def configure_vbox(vb, name, cpu, mem)
    vb.cpus = cpu
    vb.memory = mem
    vb.customize ["modifyvm", :id, "--groups", "/#{CLUSTER_NAME}"]
    
    # Création disque 100GB supplémentaire
    disk_path = ".vagrant/machines/#{name}/virtualbox/extra_disk.vdi"
    unless File.exist?(disk_path)
      FileUtils.mkdir_p(File.dirname(disk_path))
      vb.customize ['createhd', '--filename', disk_path, '--size', 102400]
    end
    vb.customize ['storageattach', :id, '--storagectl', 'SATA Controller', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', disk_path]
  end

  # ==========================
  # MASTER NODE
  # ==========================
  config.vm.define "master" do |master|
    master.vm.hostname = "master-node"
    master.vm.network "private_network", ip: CONTROL_IP
    
    master.vm.provider "virtualbox" do |vb|
      configure_vbox(vb, "master", VM_CPUS, VM_MEMORY)
    end

    master.vm.provision "common", type: "shell", path: "scripts/common.sh",
      env: { "DNS_SERVERS" => DNS_SERVERS, "KUBERNETES_VERSION" => K8S_VERSION, "OS" => OS_VERSION }
    
    master.vm.provision "master-init", type: "shell", path: "scripts/master.sh",
      env: { "CONTROL_IP" => CONTROL_IP, "POD_CIDR" => POD_CIDR, "SERVICE_CIDR" => SVC_CIDR }

    master.vm.provision "dashboard", type: "shell", path: "scripts/dashboard.sh",
      env: { "DASHBOARD_ENABLED" => "latest" }
  end

  # ==========================
  # WORKER NODES
  # ==========================
  (1..WORKER_COUNT).each do |i|
    node_name = "node0#{i}"
    config.vm.define node_name do |node|
      node.vm.hostname = "worker-node0#{i}"
      node.vm.network "private_network", ip: "192.168.56.#{10 + i}"
      
      node.vm.provider "virtualbox" do |vb|
        configure_vbox(vb, node_name, VM_CPUS, VM_MEMORY)
      end

      node.vm.provision "common", type: "shell", path: "scripts/common.sh",
        env: { "DNS_SERVERS" => DNS_SERVERS, "KUBERNETES_VERSION" => K8S_VERSION, "OS" => OS_VERSION }
      
      node.vm.provision "node-join", type: "shell", path: "scripts/node.sh"
    end
  end
end