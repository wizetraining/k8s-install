#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

source /etc/lsb-release
if [ "$DISTRIB_RELEASE" != "22.04" ]; then
    echo "################################# "
    echo "############ WARNING ############ "
    echo "################################# "
    echo
    echo "This script only works on Ubuntu 22.04!"
    echo "You're using: ${DISTRIB_DESCRIPTION}"
    echo "Better ABORT with Ctrl+C. Or press any key to continue the install"
    read
fi

KUBE_VERSION=1.35.4

# get platform
PLATFORM=`uname -p`

if [ "${PLATFORM}" == "aarch64" ]; then
  PLATFORM="arm64"
elif [ "${PLATFORM}" == "x86_64" ]; then
  PLATFORM="amd64"
else
  echo "${PLATFORM} has to be either amd64 or arm64/aarch64. Check containerd supported binaries page"
  echo "https://github.com/containerd/containerd/blob/main/docs/getting-started.md#option-1-from-the-official-binaries"
  exit 1
fi

###

# ----------------------------------------------------------------------------
# LVM CONFIGURATION FOR LONGHORN
# ----------------------------------------------------------------------------
echo "Configuring LVM for Longhorn storage..."

# Variables
DISK_DEV="/dev/sdb"
VG_NAME="longhorn-vg"
LV_NAME="longhorn-lv"
MOUNT_POINT="/var/lib/longhorn"

# 1. Install LVM2 if not present
if ! command -v pvcreate &> /dev/null; then
    echo "Installing lvm2..."
    apt-get update -y
    apt-get install -y lvm2
fi

# 2. Check if the disk exists
if [ -b "$DISK_DEV" ]; then
    
    # Check if PV exists, if not create it
    if ! pvs "$DISK_DEV" >/dev/null 2>&1; then
        echo "Creating Physical Volume on $DISK_DEV..."
        pvcreate "$DISK_DEV"
    fi

    # Check if VG exists, if not create it
    if ! vgs "$VG_NAME" >/dev/null 2>&1; then
        echo "Creating Volume Group $VG_NAME..."
        vgcreate "$VG_NAME" "$DISK_DEV"
    fi

    # Check if LV exists, if not create it (using 100% of the disk)
    if ! lvs "$VG_NAME/$LV_NAME" >/dev/null 2>&1; then
        echo "Creating Logical Volume $LV_NAME..."
        lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME"
    fi

    # Define the device path for the new LV
    LV_DEVICE="/dev/$VG_NAME/$LV_NAME"

    # 3. Format the LV with ext4 if it doesn't have a filesystem
    if ! blkid "$LV_DEVICE" >/dev/null 2>&1; then
        echo "Formatting $LV_DEVICE with ext4..."
        mkfs.ext4 "$LV_DEVICE"
    fi

    # 4. Create Mount Point
    mkdir -p "$MOUNT_POINT"

    # 5. Mount the disk
    if ! mountpoint -q "$MOUNT_POINT"; then
        echo "Mounting $LV_DEVICE to $MOUNT_POINT..."
        mount "$LV_DEVICE" "$MOUNT_POINT"
    fi

    # 6. Add to /etc/fstab for persistence
    # We use the UUID to be safe, though /dev/mapper/... is also common for LVM
    UUID=$(blkid -s UUID -o value "$LV_DEVICE")
    if ! grep -q "$UUID" /etc/fstab; then
        echo "Adding entry to /etc/fstab..."
        echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" >> /etc/fstab
    fi

    echo "LVM Setup Complete. Status:"
    lvs -o lv_name,vg_name,lv_size,lv_attr
    df -h | grep "$MOUNT_POINT"

else
    echo "WARNING: Disk $DISK_DEV not found! Skipping LVM setup."
fi


### setup terminal
apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y bash-completion binutils 
echo 'colorscheme ron' >> ~/.vimrc
echo 'set tabstop=2' >> ~/.vimrc
echo 'set shiftwidth=2' >> ~/.vimrc
echo 'set expandtab' >> ~/.vimrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'alias c=clear' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc


### disable linux swap and remove any existing swap partitions
swapoff -a
sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab


### remove packages
kubeadm reset -f || true
crictl rm --force $(crictl ps -a -q) || true
apt-mark unhold kubelet kubeadm kubectl kubernetes-cni || true
apt-get remove -y docker.io containerd kubelet kubeadm kubectl kubernetes-cni || true
apt-get autoremove -y
systemctl daemon-reload



### install podman
# . /etc/os-release
# echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
# curl -L "http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | sudo apt-key add -
# apt-get update -qq
# apt-get -qq -y install podman cri-tools containers-common
# rm /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
# cat <<EOF | sudo tee /etc/containers/registries.conf
# [registries.search]
# registries = ['docker.io']
# EOF


### install packages
apt-get install -y apt-transport-https ca-certificates open-iscsi nfs-common cryptsetup dmsetup
mkdir -p /etc/apt/keyrings
rm /etc/apt/keyrings/kubernetes-1-35-apt-keyring.gpg || true
rm /etc/apt/keyrings/kubernetes-1-34-apt-keyring.gpg || true
rm /etc/apt/keyrings/kubernetes-1-33-apt-keyring.gpg || true
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-35-apt-keyring.gpg
echo > /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1-35-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y containerd kubelet=${KUBE_VERSION}-1.1 kubeadm=${KUBE_VERSION}-1.1 kubectl=${KUBE_VERSION}-1.1 kubernetes-cni
apt-mark hold kubelet kubeadm kubectl kubernetes-cni


### install containerd 2.2
wget https://github.com/containerd/containerd/releases/download/v2.2.0/containerd-2.2.0-linux-${PLATFORM}.tar.gz
tar xvf containerd-2.2.0-linux-${PLATFORM}.tar.gz
systemctl stop containerd
mv bin/* /usr/bin
rm -rf bin containerd-2.2.0-linux-${PLATFORM}.tar.gz
systemctl unmask containerd
systemctl start containerd


### containerd
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
sudo modprobe iscsi_tcp
sudo modprobe dm_crypt
sudo modprobe nfs
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
sudo mkdir -p /etc/containerd


### containerd config
cat > /etc/containerd/config.toml <<EOF
version = 3
root = "/var/lib/containerd"
state = "/run/containerd"
oom_score = 0

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

  [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF


### crictl uses containerd as default
{
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
}


### kubelet should use containerd
{
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS="--container-runtime-endpoint unix:///run/containerd/containerd.sock"
EOF
}



### start services
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
systemctl enable kubelet && systemctl start kubelet
