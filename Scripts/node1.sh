#! /bin/bash

### If this setup based on VMware Workstation ###
# Make sure all cluster VMs have mount shread directory called Ubuntu-cluster to this env. script and shared data
# sudo mkdir /mnt/hgfs; sudo vmhgfs-fuse .host:/ /mnt/hgfs/ -o allow_other -o uid=1000 # To mount the share into Ubuntu VM


# Script declarations
current_pwd=$(pwd)
k8s_pods_network_cidr=10.100.100.0/24
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
mkdir -p /opt/k8s/custom_resources/{accounts,calico,metrics,prometheus}
mkdir -p /etc/systemd/system/docker.service.d
mkdir -p $HOME/.kube; mkdir -p /home/vagrant/.kube

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


# Initialize the K8s master node
systemctl enable kubelet
systemctl restart kubelet
kubeadm config images pull

kubeadm init --pod-network-cidr=$k8s_pods_network_cidr
# --apiserver-advertise-address 10.10.10.101 --control-plane-endpoint 10.10.10.101

cp /etc/kubernetes/admin.conf $HOME/.kube/config; cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config; chown -R vagrant:vagrant /home/vagrant/.kube

# Remove all taints from all K8s master nodes
# kubectl taint nodes --all node-role.kubernetes.io/master-

# Install K8s Network plugin - Calico
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
wget https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml -O /opt/k8s/custom_resources/calico/custom-resources.yaml
sed -i "s|192.168.0.0/16|$k8s_pods_network_cidr|" /opt/k8s/custom_resources/calico/custom-resources.yaml
kubectl apply -f /opt/k8s/custom_resources/calico/custom-resources.yaml


# Set up K8s dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended.yaml
kubectl --namespace kubernetes-dashboard patch svc kubernetes-dashboard -p '{"spec": {"type": "NodePort"}}'


# Cluster permissions
## Create Admin service account
k8s_admin_permission_token=k8s-dashboard
cat >> /opt/k8s/custom_resources/accounts/$k8s_admin_permission_token.yaml << EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $k8s_admin_permission_token
  namespace: kube-system
EOF

## Create Cluster role binding
cat >> /opt/k8s/custom_resources/accounts/${k8s_admin_permission_token}-rbac.yaml << EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $k8s_admin_permission_token
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: $k8s_admin_permission_token
    namespace: kube-system
EOF


## Apply custom permission configurations
kubectl apply -f /opt/k8s/custom_resources/accounts/$k8s_admin_permission_token.yaml
kubectl apply -f /opt/k8s/custom_resources/accounts/${k8s_admin_permission_token}-rbac.yaml

## Check for the generated token
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep ${k8s_admin_permission_token} | awk '{print $1}') | grep '^token:' | tr -s ' ' | cut -d ' ' -f2 > $shared_path/tmp/k8s_dashboard_token-$(date +"%d-%m-%y--%H-%M")

# Metrics server
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -O /opt/k8s/custom_resources/metrics/metrics-server-components.yaml
# Edit that file, under: containers -> name: metrics-server -> args -> - --secure-port=4443 add the line below
# - --kubelet-insecure-tls
kubectl apply -f /opt/k8s/custom_resources/metrics/metrics-server-components.yaml

# Kube-Prometheus
## Import Git repository
cd /opt/k8s/custom_resources/prometheus
git clone https://github.com/prometheus-operator/kube-prometheus.git
cd kube-prometheus

## Apply into the K8s cluster
kubectl apply --server-side -f manifests/setup
until kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done
kubectl apply -f manifests/

## Configuring access via NodePort
kubectl --namespace monitoring patch svc prometheus-k8s -p '{"spec": {"type": "NodePort"}}'
kubectl --namespace monitoring patch svc alertmanager-main -p '{"spec": {"type": "NodePort"}}'
kubectl --namespace monitoring patch svc grafana -p '{"spec": {"type": "NodePort"}}'

IP_ADDR=`INTERFACE=$(route | grep ^default | sed "s/.* //"); ip addr show $INTERFACE | grep 'inet ' | tr -s ' ' | cut -d ' ' -f 3 | cut -d '/' -f 1`
kubeadm token create --print-join-command | sed "s/${IP_ADDR}/$(hostname)/" > $shared_path/tmp/k8s_cluster_token.sh
if [[ ! `grep $(hostname) $shared_path/tmp/k8s_cluster_token.enc` ]]; then
  echo -e "[ERR]\tError has occured and K8s cluster token was not created well, please fix it"
  echo 'Or manually add new worker nodes using: `kubeadm token create --print-join-command`'
fi
