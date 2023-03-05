#! /bin/bash

### If this setup based on VMware Workstation ###
# Make sure all cluster VMs have mount shread directory called Ubuntu-cluster to this env. script and shared data
# sudo mkdir /mnt/hgfs; sudo vmhgfs-fuse .host:/ /mnt/hgfs/ -o allow_other -o uid=1000 # To mount the share into Ubuntu VM

# Check the HW this OS running on
# if [[ `dmidecode -s system-product-name` == 'VirtualBox' ]]; then
if [ -d /vagrant ]; then
  IP_ADDR=$(getent hosts ${hostname} | awk '{print $1}' | grep -v '127.0' | grep -v '172.17' | grep -v '10.0.2.15' | head -n1)
  shared_path=/vagrant

  # SSHD configuration
  sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  systemctl restart sshd

elif [[ `dmidecode -s system-product-name` == 'VMware Virtual Platform' ]]; then
  shared_path=/mnt/hgfs/Ubuntu-cluster/tmp
  IP_ADDR=`INTERFACE=$(route | grep ^default | sed "s/.* //" | tail -n 1); ip addr show $INTERFACE | grep 'inet ' | tr -s ' ' | cut -d ' ' -f 3 | cut -d '/' -f 1`
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
CA_LIFE_TIME='3650'
CA_NAME='k8s-playground-ca'
k8s_pods_network_cidr=10.100.100.0/24

# Disable SWAP
swapoff -a
sed -i.bak "/swap/ s/^/#/" /etc/fstab

# Generate a new CA Authority SSL certificate
if [[ ${PROVISION_SELF_SIGNED_CA_CRT} == "true" ]]; then
  if [ ! -f /etc/pki/tls/keys/${CA_NAME}.key ]; then
    mkdir -p /etc/pki/tls/{certs,keys} &> /dev/null
    openssl genrsa -out /etc/pki/tls/keys/${CA_NAME}.key 4096
    openssl req -x509 -new -nodes -key /etc/pki/tls/keys/${CA_NAME}.key -days ${CA_LIFE_TIME} -sha256 -out /etc/pki/tls/certs/${CA_NAME}.crt -subj "/CN=${CA_NAME}"
    cp /etc/pki/tls/certs/${CA_NAME}.crt /usr/local/share/ca-certificates/; cp /etc/pki/tls/certs/${CA_NAME}.crt $shared_path/
    update-ca-certificates
  fi
fi

# Setting up repositories
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt-add-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list

## Install packages
apt update; apt install -y apt-transport-https ca-certificates curl git golang gnupg2 helm jq software-properties-common vim wget
apt install -y containerd=1.5.9* cri-tools=1.25.0-00 kubeadm=1.24.7-00 kubectl=1.24.7-00 kubelet=1.24.7-00
apt-mark hold containerd cri-tools kubeadm kubectl kubelet

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

# Create required directories
mkdir -p /etc/containerd
mkdir -vp /opt/k8s/custom_resources/calico
mkdir -vp $HOME/.kube; mkdir -p /home/vagrant/.kube

# Configure Containerd
containerd config default | sudo tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# Initialize Kubernetes cluster
kubeadm config images pull
kubeadm init --pod-network-cidr=$k8s_pods_network_cidr --apiserver-advertise-address $IP_ADDR

cp -v /etc/kubernetes/admin.conf $HOME/.kube/config; cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config; cp /etc/kubernetes/admin.conf $shared_path/kubectl_config
chown -v $(id -u):$(id -g) $HOME/.kube/config; chown -R vagrant:vagrant /home/vagrant/.kube

# [Optional] Remove all taints from all K8s master nodes
# kubectl taint nodes --all node-role.kubernetes.io/master-
# kubectl taint nodes --all node-role.kubernetes.io/control-plane-


# Define a CA Authority Secret
if [[ ${PROVISION_SELF_SIGNED_CA_CRT} == "true" ]]; then
  kubectl create namespace ssl-ready
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${CA_NAME}-secret
  namespace: ssl-ready
type: Opaque
data:
  tls.crt: $(cat /etc/pki/tls/certs/${CA_NAME}.crt | base64 -w 0)
  tls.key: $(cat /etc/pki/tls/keys/${CA_NAME}.key | base64 -w 0)
EOF
fi


# Install K8s Network plugin - Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
wget https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml -O /opt/k8s/custom_resources/calico/custom-resources.yaml
sed -i "s|192.168.0.0/16|$k8s_pods_network_cidr|" /opt/k8s/custom_resources/calico/custom-resources.yaml
kubectl apply -f /opt/k8s/custom_resources/calico/custom-resources.yaml


# Set up K8s dashboard, COMMENTED OUT DUE TO -> being unable to get K8s dashboard token
# helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
# helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard
# kubectl -n default patch svc kubernetes-dashboard -p '{"spec": {"type": "NodePort"}}'

# Cluster permissions
## Create Admin service account
# k8s_admin_permission_token=k8s-dashboard

# kubectl create serviceaccount $k8s_admin_permission_token
# kubectl create clusterrolebinding $k8s_admin_permission_token --clusterrole=cluster-admin --serviceaccount=kube-system:$k8s_admin_permission_token


# cat >> /opt/k8s/custom_resources/accounts/$k8s_admin_permission_token.yaml << EOF
# ---
# apiVersion: v1
# kind: ServiceAccount
# metadata:
#   name: $k8s_admin_permission_token
#   namespace: kube-system
# EOF

## Create Cluster role binding
# cat >> /opt/k8s/custom_resources/accounts/${k8s_admin_permission_token}-rbac.yaml << EOF
# ---
# apiVersion: rbac.authorization.k8s.io/v1
# kind: ClusterRoleBinding
# metadata:
#   name: $k8s_admin_permission_token
# roleRef:
#   apiGroup: rbac.authorization.k8s.io
#   kind: ClusterRole
#   name: cluster-admin
# subjects:
#   - kind: ServiceAccount
#     name: $k8s_admin_permission_token
#     namespace: kube-system
# EOF


## Apply custom permission configurations
# kubectl apply -f /opt/k8s/custom_resources/accounts/$k8s_admin_permission_token.yaml
# kubectl apply -f /opt/k8s/custom_resources/accounts/${k8s_admin_permission_token}-rbac.yaml

## Check for the generated token
# kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep ${k8s_admin_permission_token} | awk '{print $1}') | grep '^token:' | tr -s ' ' | cut -d ' ' -f2 > $shared_path/k8s_dashboard_token-$(date +"%d-%m-%y--%H-%M")


# Rook-Ceph Storage-Forest
if [[ ${PROVISION_CEPH} == "true" ]]; then
  cp /vagrant/Playground/Helm/Rook-Ceph/cronjob /etc/cron.d/rook-ceph-setup
  echo 'Rook provision will start in 5mis, via Cronjob...'
  echo 'You can watch its provision log at: /var/log/k8s-rook-ceph.log'
fi


# Cert-Manager
if [[ ${PROVISION_CERT_MANAGER} == "true" ]]; then
  cp /vagrant/Playground/Helm/Cert-Manager/cronjob /etc/cron.d/cert-manager-setup
  echo 'Cert-Manager provision will start in 5mis, via Cronjob...'
  echo 'You can watch its provision log at: /var/log/cert-manager.log'
fi


# Kube-Prometheus
## ToDos:
### Install via Helm
### Install & play with Grafana Loki

## Custromized Prometheus stack setup ###
# Install some Go packages
for PACKAGE in "github.com/brancz/gojsontoyaml" "github.com/google/go-jsonnet/cmd/jsonnet" "github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb"; do
  go install -v ${PACKAGE}@latest
done
export PATH=$PATH:/root/go/bin/

# Clone the project
mkdir /opt/k8s/custom_resources/prometheus-jsonnet; cd /opt/k8s/custom_resources/prometheus-jsonnet
jb init

# The below was confirmed to work with release-0.11 with K8s 1.24.7, Check comptability at: https://github.com/prometheus-operator/kube-prometheus
jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@main
for FILE in "build.sh" "example.jsonnet"; do
  wget https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/$FILE -O $FILE
done

sed -i "s|// (import 'kube-prometheus/addons/node-ports.libsonnet') +|(import 'kube-prometheus/addons/node-ports.libsonnet') +|g" example.jsonnet
sed -i "/pyrra.libsonnet/ a \ \ (import 'kube-prometheus/addons/networkpolicies-disabled.libsonnet') +" example.jsonnet
bash ./build.sh

kubectl apply --server-side -f manifests/setup
kubectl wait \
	--for condition=Established \
	--all CustomResourceDefinition \
	--namespace=monitoring
kubectl apply -f manifests/
###


# Default Playground configurations:
kubectl create -f /vagrant/Playground/Yamls/Default/PriorityClasses/default.yaml
kubectl create -f /vagrant/Playground/Yamls/Default/NameSpaces/default.yaml


kubeadm token create --print-join-command | sed "s/${IP_ADDR}/$(hostname)/" > $shared_path/k8s_cluster_token.sh
if [[ ! `grep $(hostname -f) $shared_path/k8s_cluster_token.sh 2> /dev/null` ]]; then
  echo -e "[ERR]\tError has occured and K8s cluster token was not created well, please fix it"
  echo 'Or manually add new worker nodes using: `kubeadm token create --print-join-command`'
fi
