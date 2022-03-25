#! /bin/bash

### If this setup based on VMware Workstation ###
# Make sure all cluster VMs have mount shread directory called Ubuntu-cluster to this env. script and shared data
# sudo mkdir /mnt/hgfs; sudo vmhgfs-fuse .host:/ /mnt/hgfs/ -o allow_other -o uid=1000 # To mount the share into Ubuntu VM

# Script declarations
shared_path=/mnt/hgfs/Ubuntu-cluster

# Dependecy checks
if [[ ! -d $shared_path ]]; then
  echo 'Shared directory path does not exists!'
  exit 1
fi


# Disable SWAP
swapoff -a
sed -i.bak "/swap/ s/^/#/" /etc/fstab

# Updating the OS distribution
## Setting up repositories
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
apt-add-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

## Install packages
apt update; apt install -y ca-certificates curl git gnupg2 jq software-properties-common vim wget \
kubeadm kubectl kubelet \
containerd.io docker-ce docker-ce-cli

apt-mark hold kubeadm kubectl kubelet

# Enable kernel modules
modprobe overlay
modprobe br_netfilter

# Add custom settings to sysctl
cat >> /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# Create required directories
mkdir -p /etc/systemd/system/docker.service.d

# Create daemon configuration file for Docker
cat >> /etc/docker/daemon.json << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload 
systemctl enable docker
systemctl restart docker

systemctl enable kubelet
systemctl restart kubelet

if [[ -f /mnt/hgfs/Ubuntu-cluster/tmp/k8s_cluster_token.sh ]]; then
  echo -e "[INFO]\tAdding node to an Active K8s cluster..."
  /mnt/hgfs/Ubuntu-cluster/tmp/k8s_cluster_token.sh
else
  echo -e "[ERR]\tCould not automatically add node to an Active K8s cluster - please do so manually!"
fi
