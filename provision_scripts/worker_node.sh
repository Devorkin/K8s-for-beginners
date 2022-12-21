#! /bin/bash

### If this setup based on VMware Workstation ###
# Make sure all cluster VMs have mount shread directory called Ubuntu-cluster to this env. script and shared data
# sudo mkdir /mnt/hgfs; sudo vmhgfs-fuse .host:/ /mnt/hgfs/ -o allow_other -o uid=1000 # To mount the share into Ubuntu VM

# Check the HW this OS running on
if [ -d /vagrant ]; then
  shared_path=/vagrant
  IP_ADDR=$(getent hosts ${hostname} | awk '{print $1}' | grep -v '127.0' | grep -v '172.17' | grep -v '10.0.2.15' | head -n1)

  # SSHD configuration
  cat /vagrant/authorized_keys >> ~/.ssh/authorized_keys
  sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  systemctl restart sshd

elif [[ `dmidecode -s system-product-name` == 'VMware Virtual Platform' ]]; then
  shared_path=/mnt/hgfs/Ubuntu-cluster/tmp
fi

# Dependecy checks
if [[ ! -d $shared_path ]]; then
  echo 'Shared directory path does not exists!'
  exit 1
fi

# Script declarations
# k8s_node_max_pods=90

# Disable SWAP
swapoff -a
sed -i.bak "/swap/ s/^/#/" /etc/fstab

# Setting up repositories
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt-add-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list

## Install packages
apt update; apt install -y apt-transport-https ca-certificates curl git gnupg2 jq software-properties-common vim wget
apt install -y containerd kubeadm=1.24.7-00 kubectl=1.24.7-00 kubelet=1.24.7-00
apt-mark hold containerd helm kubeadm kubectl kubelet

# Enable kernel modules
modprobe overlay
modprobe br_netfilter
echo -e "br_netfilter\noverlay" >> /etc/modules-load.d/containerd.conf

# Add custom settings to sysctl
cat >> /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system 2> /dev/null

### TEST: Change maxPods in Kubelet ###
# service_name=$(systemctl list-unit-files | grep kubelet | cut -d ' ' -f1)
# kubelet_svc=$(ls -1 /etc/systemd/system/$service_name.d/)
# KUBELET_KUBECONFIG_ARGS_LINE=$(grep "KUBELET_KUBECONFIG_ARGS=" /etc/systemd/system/$service_name.d/$kubelet_svc | cut -d '"' -f2)
# NEW_KUBELET_KUBECONFIG_ARGS="${KUBELET_KUBECONFIG_ARGS_LINE} --max-pods $k8s_node_max_pods"
# sed -i "s|${KUBELET_KUBECONFIG_ARGS_LINE}|${NEW_KUBELET_KUBECONFIG_ARGS}|g" /etc/systemd/system/$service_name.d/$kubelet_svc

# Create required directories
mkdir -p /etc/containerd

# Configure Containerd
containerd config default | sudo tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

if [[ -f ${shared_path}/k8s_cluster_token.sh ]]; then
  echo -e "[INFO]\tAdding node to an Active K8s cluster..."
  bash ${shared_path}/k8s_cluster_token.sh 2> /dev/null
else
  echo -e "[ERR]\tCould not automatically add node to an Active K8s cluster - please do so manually!"
fi

# if [ -d /vagrant ]; then
#   echo "KUBELET_CONFIG_ARGS=\"--node-ip ${IP_ADDR}\"" >> /var/lib/kubelet/kubeadm-flags.env
#   systemctl restart kubelet
# fi
