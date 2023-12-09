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
apt-add-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
if [ ! -f /etc/apt/sources.list.d/helm-stable-debian.list ]; then
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" > /etc/apt/sources.list.d/helm-stable-debian.list
fi

## Install packages
apt update; apt install -y apt-transport-https ca-certificates curl git gnupg2 jq software-properties-common vim wget

for package in ${confirm_installed_packages[@]}; do apt-mark unhold ${package}; done

k8s_installation_cmd="apt install -y containerd=${containerd_version} cri-tools=${cri_version}"
for package in ${k8s_packages[@]}; do k8s_installation_cmd+=" ${package}=${k8s_packages_version}"; done
${k8s_installation_cmd}

for i in ${confirm_installed_packages[@]}; do
  if [ $all_k8s_packages_installed == 'true' ] && ! dpkg -l | grep ${i} &> /dev/null; then
    all_k8s_packages_installed='false'
  fi
done
if [[ $all_k8s_packages_installed == 'true' ]]; then
  for package in ${confirm_installed_packages[@]}; do apt-mark hold ${package}; done
fi

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
