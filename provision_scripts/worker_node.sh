#! /bin/bash

### If this setup based on VMware Workstation ###
# Make sure all cluster VMs have mount shread directory called Ubuntu-cluster to this env. script and shared data
# sudo mkdir /mnt/hgfs; sudo vmhgfs-fuse .host:/ /mnt/hgfs/ -o allow_other -o uid=1000 # To mount the share into Ubuntu VM

# Check the HW this OS running on
if [ -d /vagrant ]; then
  ip_addr=$(getent hosts ${hostname} | awk '{print $1}' | grep -v '127.0' | grep -v '172.17' | grep -v '10.0.2.15' | head -n1)
  shared_path=/vagrant/Shared_between_nodes

  # SSHD configuration
  if sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config; then systemctl restart sshd; fi

elif [[ `dmidecode -s system-product-name` == 'VMware Virtual Platform' ]]; then
  shared_path=/mnt/hgfs/Ubuntu-cluster/tmp
fi

# Dependecy checks
if [[ ! -d $shared_path ]]; then
  echo 'Shared directory path does not exists!'
  exit 1
fi

# EXIT IF MASTER NODE AIN'T WORKING PROPERLLY
return_value=$(cat $shared_path/vagrant_k8s_for_begginers.exitcode)
if [ $return_value == 1 ]; then
  echo "K8s Master node failed to provision - please fix it; and then re-run `vagrant up` per each requested node"
  exit 1
fi

# Script declarations
source /vagrant/provision_scripts/provision_variables.cnf
all_k8s_packages_installed='true'
ca_name='k8s-playground-ca'
# k8s_node_max_pods=90
K8S_STABLE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
K8S_TOOLS_VERSION=${K8S_STABLE_VERSION%.*}

# Disable SWAP
swapoff -a
sed -i.bak "/swap/ s/^/#/" /etc/fstab

# Trust this K8s cluster CA Authority SSL certificate
if [ -f $shared_path/${ca_name}.crt ]; then
  cp $shared_path/${ca_name}.crt /usr/local/share/ca-certificates/
  update-ca-certificates
fi

# Setting up repositories
if [ ! -f /usr/share/keyrings/helm.gpg ]; then curl -s https://baltocdn.com/helm/signing.asc | gpg --dearmor > /usr/share/keyrings/helm.gpg; fi
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
if [ ! -f /etc/apt/sources.list.d/helm-stable-debian.list ]; then
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" > /etc/apt/sources.list.d/helm-stable-debian.list
fi

mkdir -p /etc/apt/keyrings 2> /dev/null
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_STABLE_VERSION%.*}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_STABLE_VERSION%.*}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

## Install packages
apt update; apt install -y $(echo $apt_packages_to_install)
snap install yq

# Cleanup after ETCD, as we only need its client-end
systemctl stop etcd; systemctl disable etcd; rm -rf /var/lib/etcd

for package in ${confirm_installed_packages[@]}; do apt-mark unhold ${package}; done

k8s_installation_cmd="apt install -y containerd cri-tools=${K8S_TOOLS_VERSION:1}*"
for package in ${k8s_packages[@]}; do k8s_installation_cmd+=" ${package}=${K8S_TOOLS_VERSION:1}*"; done
${k8s_installation_cmd}
if [ $? != 0 ]; then
  echo 'Fail to install a REQUIERMENT package; Kubernetes cluster setup process will be aborted now!'
  exit 2
fi

for i in ${confirm_installed_packages[@]}; do
  if [ $all_k8s_packages_installed == 'true' ] && ! dpkg -l | grep ${i} &> /dev/null; then
    all_k8s_packages_installed='false'
  fi
done
if [[ $all_k8s_packages_installed == 'true' ]]; then
  for package in ${confirm_installed_packages[@]}; do apt-mark hold ${package}; done
fi

## Configure packages
echo "alias cat='batcat'" > ~/.bashrc
echo "alias diff='diff --color'" > ~/.bashrc

# Enable kernel modules
modprobe overlay
modprobe br_netfilter
if [ ! -f /etc/modules-load.d/containerd.conf ]; then echo -e "br_netfilter\noverlay" > /etc/modules-load.d/containerd.conf; fi

# Add custom settings to sysctl
if [ ! -f /etc/sysctl.d/kubernetes.conf ]; then
cat >> /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.max_map_count=262144
EOF
  sysctl --system 2> /dev/null
fi

### TEST: Change maxPods in Kubelet ###
# service_name=$(systemctl list-unit-files | grep kubelet | cut -d ' ' -f1)
# kubelet_svc=$(ls -1 /etc/systemd/system/$service_name.d/)
# KUBELET_KUBECONFIG_ARGS_LINE=$(grep "KUBELET_KUBECONFIG_ARGS=" /etc/systemd/system/$service_name.d/$kubelet_svc | cut -d '"' -f2)
# NEW_KUBELET_KUBECONFIG_ARGS="${KUBELET_KUBECONFIG_ARGS_LINE} --max-pods $k8s_node_max_pods"
# sed -i "s|${KUBELET_KUBECONFIG_ARGS_LINE}|${NEW_KUBELET_KUBECONFIG_ARGS}|g" /etc/systemd/system/$service_name.d/$kubelet_svc

# Create required directories
mkdir -p /etc/containerd &> /dev/null

# Configure Containerd
if [ ! -f /etc/containerd/config.toml ]; then containerd config default > /etc/containerd/config.toml; fi
if sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml; then systemctl restart containerd; fi

# Add directories, that may be used as PVs
mkdir -p /mnt/vault/{audit,data}

if ! systemctl status kubelet &> /dev/null; then
  if [[ -f ${shared_path}/k8s_cluster_token.sh ]]; then
    echo -e "[INFO]\tAdding node to an Active K8s cluster..."
    bash ${shared_path}/k8s_cluster_token.sh 2> /dev/null
  else
    echo -e "[ERR]\tCould not automatically add node to an Active K8s cluster - please do so manually!"
  fi
fi

# if [ -d /vagrant ]; then
#   echo "KUBELET_CONFIG_ARGS=\"--node-ip ${ip_addr}\"" >> /var/lib/kubelet/kubeadm-flags.env
#   systemctl restart kubelet
# fi

# Setting up Playground directories (For Local storageClass)
mkdir /mnt/k8s-local-storage
