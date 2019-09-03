#! /bin/bash

# Install needed packages
apt update && apt install -y httping

git clone https://github.com/otomato-gh/container.training.git
./container.training/prepare-vms/setup_kubeadm.sh

# Get the "Join" command from the K8s cluster master
# For example:
# sudo kubeadm join 192.168.70.8:6443 --token 56j969.6jgjdjauvvckdx50     --discovery-token-ca-cert-hash sha256:ebc2ec8ceb8a1ffc2573346e7f82f617689d0ac91fd48c2f407b329276110b16

exit 0