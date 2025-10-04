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
K8S_STABLE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
K8S_TOOLS_VERSION=${K8S_STABLE_VERSION%.*}

# Disable SWAP
swapoff -a
sed -i.bak "/swap/ s/^/#/" /etc/fstab

# Cleanup old Vagrant VMs cache
if [ -f $shared_path/k8s_cluster_token.sh ]; then rm -f $shared_path/k8s_cluster_token.sh; fi
if [ -f $shared_path/vagrant_k8s_for_beginners.exitcode ]; then rm -f $shared_path/vagrant_k8s_for_beginners.exitcode; fi

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
if [ ! -f /etc/apt/sources.list.d/helm-stable-debian.list ]; then
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" > /etc/apt/sources.list.d/helm-stable-debian.list
fi

mkdir -p /etc/apt/keyrings 2> /dev/null
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_STABLE_VERSION%.*}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_STABLE_VERSION%.*}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

## Install packages
export DEBIAN_FRONTEND=noninteractive
apt update; apt install -y $(echo $apt_packages_to_install); apt install -y golang helm --no-install-recommends
snap install yq

# Cleanup after ETCD, as we only need its client-end
systemctl stop etcd; systemctl disable etcd; rm -rf /var/lib/etcd

for package in ${confirm_installed_packages[@]}; do apt-mark unhold ${package}; done

k8s_installation_cmd="apt install -y containerd cri-tools=${K8S_TOOLS_VERSION:1}* --no-install-recommends"
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


# Yehonatan D. initial Playground K8s cluster configurations:
kubectl create -f /vagrant/Playground/Yamls/Default/PriorityClasses/default.yaml
kubectl create -f /vagrant/Playground/Yamls/Default/NameSpaces/default.yaml
kubectl create -f /vagrant/Playground/Yamls/Default/StorageClass/StorageClass.yaml
kubectl create -f /vagrant/Playground/Yamls/Default/StorageClass/PersistentVolume.yaml
###


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
###


# Rook-Ceph Storage-Forest
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [[ ${PROVISION_CEPH} == "true" ]]; then
    cp /vagrant/Playground/Helm/Rook-Ceph/cronjob /etc/cron.d/rook-ceph-setup
    echo 'Rook provision will start in 5mis, via Cronjob...'
    echo 'You can watch its provision log at: /var/log/k8s-rook-ceph.log'

    # Setting a LOCK file - for other features to look for, and wait until it is erased
    touch /var/lock/rook-ceph.lck
  fi
fi
###


# Cert-Manager
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [[ ${PROVISION_CERT_MANAGER} == "true" ]]; then
    cp /vagrant/Playground/Helm/Cert-Manager/cronjob /etc/cron.d/cert-manager-setup
    echo 'Cert-Manager provision will start in 5mis, via Cronjob...'
    echo 'You can watch its provision log at: /var/log/cert-manager.log'
  fi
fi
###


# Ingress-Nginx
if [[ $all_k8s_packages_installed == 'true' ]]; then
  if [[ ${PROVISION_INGRESS_NGINX} == "true" ]]; then
    cp /vagrant/Playground/Helm/Ingress-Nginx/cronjob /etc/cron.d/ingress-nginx-setup
    echo 'Ingress-Nginx provision will start in 5mis, via Cronjob...'
    echo 'You can watch its provision log at: /var/log/ingress-nginx.log'
  fi
fi
###


# Prometheus
if [[ ${PROVISION_PROMETHEUS} == "true" ]]; then
  if [[ ${PROVISION_CEPH} == "true" ]]; then SETUP_MODE='Rook-Ceph'; else SETUP_MODE='Local'; fi
  cp /vagrant/Playground/Helm/Prometheus/cronjob /etc/cron.d/prometheus-setup
  sed -i "s/SETUP_MODE/${SETUP_MODE}/" /etc/cron.d/prometheus-setup
  echo 'Prometheus provision will start in 5mis, via Cronjob...'
  echo 'You can watch its provision log at: /var/log/k8s-prometheus.log'
fi
###


kubeadm token create --print-join-command | sed "s/${ip_addr}/$(hostname)/" > $shared_path/k8s_cluster_token.sh

if grep $(hostname) $shared_path/k8s_cluster_token.sh &> /dev/null; then
  echo '0' > $shared_path/vagrant_k8s_for_beginners.exitcode
else
  echo -e "[ERR]\tError has occured and K8s cluster token was not created well, please fix it"
  echo 'Or manually add new worker nodes using: `kubeadm token create --print-join-command`'
  echo '1' > $shared_path/vagrant_k8s_for_beginners.exitcode
fi
