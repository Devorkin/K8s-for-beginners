#! /bin/bash

### If this setup based on VMware Workstation ###
# Make sure all cluster VMs have mount shread directory called Ubuntu-cluster to this env. script and shared data
# sudo mkdir /mnt/hgfs; sudo vmhgfs-fuse .host:/ /mnt/hgfs/ -o allow_other -o uid=1000 # To mount the share into Ubuntu VM

# Check the HW this OS running on
# if [[ `dmidecode -s system-product-name` == 'VirtualBox' ]]; then
if [ -d /vagrant ]; then
  ip_addr=$(getent hosts ${hostname} | awk '{print $1}' | grep -v '127.0' | grep -v '172.17' | grep -v '10.0.2.15' | head -n1)
  shared_path=/vagrant/Shared_between_nodes
  if [ ! -d $shared_path ]; then mkdir $shared_path; fi

  # SSHD configuration
  if sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config; then systemctl restart sshd; fi

elif [[ `dmidecode -s system-product-name` == 'VMware Virtual Platform' ]]; then
  shared_path=/mnt/hgfs/Ubuntu-cluster/tmp
  ip_addr=`INTERFACE=$(route | grep ^default | sed "s/.* //" | tail -n 1); ip addr show $INTERFACE | grep 'inet ' | tr -s ' ' | cut -d ' ' -f 3 | cut -d '/' -f 1`
fi

# Dependecy checks
if [[ ! -d $shared_path ]]; then
  echo 'Shared directory path does not exists!'
  if [[ `dmidecode -s system-product-name` == 'VMware Virtual Platform' ]]; then
    echo 'Run the below commands to create the Share directory:'
    echo -e "# Create new Share directory\nmkdir /mnt/hgfs"
    echo -e "# Mount the share directory\nvmhgfs-fuse .host:/ /mnt/hgfs/ -o allow_other -o uid=1000"
  fi
  exit 1
fi

# Script declarations
source /vagrant/provision_scripts/provision_variables.cnf
ca_life_time='3650'
ca_name='k8s-playground-ca'
all_k8s_packages_installed='true'
k8s_pods_network_cidr=10.100.100.0/24

# Disable SWAP
swapoff -a
sed -i.bak "/swap/ s/^/#/" /etc/fstab

# Cleanup old Vagrant VMs cache
if [ -f $shared_path/k8s_cluster_token.sh ]; then rm -f $shared_path/k8s_cluster_token.sh; fi
if [ -f $shared_path/vagrant_k8s_for_begginers.exitcode ]; then rm -f $shared_path/vagrant_k8s_for_begginers.exitcode; fi

# Generate a new CA Authority SSL certificate
if [[ ${PROVISION_SELF_SIGNED_CA_CRT} == "true" ]]; then
  if [ ! -f /etc/pki/tls/keys/${ca_name}.key ]; then
    mkdir -p /etc/pki/tls/{certs,keys} &> /dev/null
    openssl genrsa -out /etc/pki/tls/keys/${ca_name}.key 4096
    openssl req -x509 -new -nodes -key /etc/pki/tls/keys/${ca_name}.key -days ${ca_life_time} -sha256 -out /etc/pki/tls/certs/${ca_name}.crt -subj "/CN=${ca_name}"
    cp /etc/pki/tls/certs/${ca_name}.crt /usr/local/share/ca-certificates/; cp /etc/pki/tls/certs/${ca_name}.crt $shared_path/
    update-ca-certificates
  fi
fi

# Setting up repositories
if [ ! -f /usr/share/keyrings/helm.gpg ]; then curl -s https://baltocdn.com/helm/signing.asc | gpg --dearmor > /usr/share/keyrings/helm.gpg; fi
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt-add-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
if [ ! -f /etc/apt/sources.list.d/helm-stable-debian.list ]; then
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" > /etc/apt/sources.list.d/helm-stable-debian.list
fi

## Install packages
apt update; apt install -y apt-transport-https ca-certificates curl git golang gnupg2 helm jq software-properties-common vim wget

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

# Create required directories
mkdir -p /etc/containerd &> /dev/null
mkdir -p /opt/k8s/custom_resources/calico &> /dev/null
mkdir -p $HOME/.kube; mkdir -p /home/vagrant/.kube &> /dev/null

# Configure Containerd
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [ ! -f /etc/containerd/config.toml ]; then containerd config default > /etc/containerd/config.toml; fi
  if sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml; then systemctl restart containerd; fi
fi

# Initialize Kubernetes cluster
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if ! systemctl status kubelet &> /dev/null; then
    kubeadm config images pull
    kubeadm init --pod-network-cidr=$k8s_pods_network_cidr --apiserver-advertise-address $ip_addr
  fi
  cp /etc/kubernetes/admin.conf $HOME/.kube/config; cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config; cp /etc/kubernetes/admin.conf $shared_path/kubectl_config
  chown $(id -u):$(id -g) $HOME/.kube/config; chown -R vagrant:vagrant /home/vagrant/.kube
fi

# [Optional] Remove all taints from all K8s master nodes
# kubectl taint nodes --all node-role.kubernetes.io/master-
# kubectl taint nodes --all node-role.kubernetes.io/control-plane-


# Define a CA Authority Secret
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [[ ${PROVISION_SELF_SIGNED_CA_CRT} == "true" ]] && ! kubectl get namespace ssl-ready &> /dev/null; then
    kubectl create namespace ssl-ready
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${ca_name}-secret
  namespace: ssl-ready
type: Opaque
data:
  tls.crt: $(cat /etc/pki/tls/certs/${ca_name}.crt | base64 -w 0)
  tls.key: $(cat /etc/pki/tls/keys/${ca_name}.key | base64 -w 0)
EOF
  fi
fi
###


# Install K8s Network plugin - Calico
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if ! kubectl get namespace tigera-operator &> /dev/null; then kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml; fi
  if [ ! -f /opt/k8s/custom_resources/calico/custom-resources.yaml ]; then wget --quiet https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml -O /opt/k8s/custom_resources/calico/custom-resources.yaml; fi
  sed -i "s|192.168.0.0/16|$k8s_pods_network_cidr|" /opt/k8s/custom_resources/calico/custom-resources.yaml
  kubectl create -f /opt/k8s/custom_resources/calico/custom-resources.yaml
fi

# Rook-Ceph Storage-Forest
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [[ ${PROVISION_CEPH} == "true" ]]; then
    cp /vagrant/Playground/Helm/Rook-Ceph/cronjob /etc/cron.d/rook-ceph-setup
    echo 'Rook provision will start in 5mis, via Cronjob...'
    echo 'You can watch its provision log at: /var/log/k8s-rook-ceph.log'
  fi
fi
###


# Cert-Manager
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [[ ${PROVISION_CERT_MANAGER} == "true" ]]; then
    if [ ! -f /etc/cron.d/cert-manager-setup ]; then cp /vagrant/Playground/Helm/Cert-Manager/cronjob /etc/cron.d/cert-manager-setup; fi
    echo 'Cert-Manager provision will start in 5mis, via Cronjob...'
    echo 'You can watch its provision log at: /var/log/cert-manager.log'
  fi
fi
###


# Ingress-Nginx
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [[ ${PROVISION_INGRESS_NGINX} == "true" ]]; then
    if [ ! -f /etc/cron.d/ingress-nginx-setup ]; then cp /vagrant/Playground/Helm/Ingress-Nginx/cronjob /etc/cron.d/ingress-nginx-setup; fi
    echo 'Ingress-Nginx provision will start in 5mis, via Cronjob...'
    echo 'You can watch its provision log at: /var/log/ingress-nginx.log'
  fi
fi
###


# Kube-Prometheus
## ToDos:
### Install via Helm
### Install & play with Grafana Loki

## Custromized Prometheus stack setup ###
# Install some Go packages
if [[ $all_k8s_packages_installed == 'true' ]]; then
  for package in "github.com/brancz/gojsontoyaml" "github.com/google/go-jsonnet/cmd/jsonnet" "github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb"; do
    go install -v ${package}@latest
  done
  export PATH=$PATH:/root/go/bin/

  # Clone the project
  mkdir /opt/k8s/custom_resources/prometheus-jsonnet 2> /dev/null; cd /opt/k8s/custom_resources/prometheus-jsonnet
  if [ ! -f jsonnetfile.json ]; then jb init; fi

  # The below was confirmed to work with Kube-prometheus release-0.11 and K8s 1.24.7, Check comptability at: https://github.com/prometheus-operator/kube-prometheus
  jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@main
  for file in "build.sh" "example.jsonnet"; do
    if [ ! -f $file ]; then wget --quiet https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/$file -O $file; fi
  done

  sed -i "s|// (import 'kube-prometheus/addons/node-ports.libsonnet') +|(import 'kube-prometheus/addons/node-ports.libsonnet') +|g" example.jsonnet
  sed -i "/pyrra.libsonnet/ a \ \ (import 'kube-prometheus/addons/networkpolicies-disabled.libsonnet') +" example.jsonnet
  if [ ! -d manifests ]; then bash ./build.sh; fi

  if ! kubectl get namespace monitoring &> /dev/null; then
    kubectl apply --server-side -f manifests/setup
    kubectl wait \
      --for condition=Established \
      --all CustomResourceDefinition \
      --namespace=monitoring
    kubectl apply -f manifests/
  fi
fi
###


# Default Playground configurations:
if [[ $all_k8s_packages_installed == 'true' ]]; then
  kubectl create -f /vagrant/Playground/Yamls/Default/PriorityClasses/default.yaml
  kubectl create -f /vagrant/Playground/Yamls/Default/NameSpaces/default.yaml

  kubeadm token create --print-join-command | sed "s/${ip_addr}/$(hostname)/" > $shared_path/k8s_cluster_token.sh
fi

if grep $(hostname) $shared_path/k8s_cluster_token.sh &> /dev/null; then
  echo '0' > $shared_path/vagrant_k8s_for_begginers.exitcode
else
  echo -e "[ERR]\tError has occured and K8s cluster token was not created well, please fix it"
  echo 'Or manually add new worker nodes using: `kubeadm token create --print-join-command`'
  echo '1' > $shared_path/vagrant_k8s_for_begginers.exitcode
fi