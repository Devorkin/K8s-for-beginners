#! /bin/bash

# Install needed packages
apt update && apt install -y httping

git clone https://github.com/otomato-gh/container.training.git
### For single node setup
#./prepare-vms/setup_minikube_sn_ub1804.sh
#kubectl get nodes

### For multi-nodes setup
./container.training/prepare-vms/setup_kubeadm.sh
#kubeadm init
kubeadm init --apiserver-advertise-address 192.168.70.8
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Deploy Weave pod network
sysctl net.bridge.bridge-nf-call-iptables=1
export kubever=$(kubectl version | base64 | tr -d '\n')
kubectl apply -f https://cloud.weave.works/k8s/net?k8s-version=$kubever

#kubectl get nodes -w
kubectl taint nodes --all node-role.kubernetes.io/master-
# kubeadm token create --print-join-command

# cd /vagrant/Git/container.training/dockercoins
#docker-compose up --scale worker=10 -d
# docker-compose logs
# docker-compose logs --tail 10 --follow
# ^S || ^Q
# docker-compose scale worker=2
# docker-compose scale worker=10
# httping -c 3 localhost:8001

#kubectl run pingpong --image alpine ping goo.gl        # "kubectl run" command is being deprecated! - use "kubectl create" instead
#kubectl get all
# top
# vmstat1 || vmstat 3
# kubectl logs deployment.apps/pingpong
# kubectl logs deployment.apps/pingpong --tail 10
# kubectl logs deployment.apps/pingpong --tail 10 --follow
# kubectl scale deploy/pingpong --replicas 8
# kubectl get pods -w
# kubectl delete pod pingpong-yyyy
# kubectl run web --image=nginx --replicas=3

### kubectl expose
## A K8s Service is a stable address for a pod(s)
## Nodes - A K8s system that holds pods\containers, etc.
# ClusterIP (default): An private virtual IP address, associated with nodes and pods to communicate between each-other
# NodePort: A service allocated port which is available on all nodes (port range is between 30000-32768) so that anybody may access it
# LoadBalancer: Used with NodePort and external Load balancer (External, means out side of the K8s system?!)
# ExternalName: A record inside CoreDNS that will be a CNAME to provided record (associated with external DNS system)
###

# kubectl get pods
# kubectl create deployment httpenv --image=otomato/httpenv
# kubectl scale deployment httpenv --replicas=10
#kubectl get service -w
# kubectl get svc
# kubectl expose deployment httpenv --port 8888
# IP=$(kubectl get svc httpenv -o json | jq -r .spec.clusterIP)
# IP=$(kubectl get svc httpenv -o go-template --template '{{ .spec.clusterIP }}')
# curl http://$IP:8888/
# curl -s http://$IP:8888/ | jq .HOSTNAME

# kubectl describe service httpenv
# kubectl get endpoints
# kubectl describe endpoints httpenv
# kubectl get endpoints httpenv -o json
# kubectl get pods -l app=httpenv -o wide
# kubectl get endpoints httpenv -o json | grep ip | cut -d ':' -f2 | sed -e 's/ "//g' -e 's/",//g'
# kubectl get pods -l app=httpenv -o wide

# kubectl delete pod ${pod_name}
# kubectl delete deployments ${deployment_name}
# kubecyl delete service ${service_name}

exit 0

kubectl run registry --image=registry:2
kubectl expose deploy/registry --port=5000 --type=NodePort
kubectl describe svc/registry
NODEPORT=$(kubectl get svc/registry -o json | jq .spec.ports[0].nodePort)
REGISTRY=127.0.0.1:$NODEPORT
#curl $REGISTRY/v2/_catalog

docker pull busybox
docker tag busybox $REGISTRY/busybox
docker push $REGISTRY/busybox
#curl $REGISTRY/v2/_catalog

cd container.training/stacks
export REGISTRY
docker-compose -f dockercoins.yml build
docker-compose -f dockercoins.yml push
kubectl create deployment redis --image=redis # The presentation commansd `kubectl run redis --image=redis` is DEPRECATED
for SERVICE in hasher rng webui worker; do
  kubectl create deployment $SERVICE --image=$REGISTRY/$SERVICE
done
# kubectl get deploy
# kubectl logs deploy/rng
# kubectl logs deploy/worker  # Should raise errors

kubectl expose deployment redis --port 6379
kubectl expose deployment rng --port 80
kubectl expose deployment hasher --port 80
kubectl expose deploy/webui --type=NodePort --port=80

exit 0