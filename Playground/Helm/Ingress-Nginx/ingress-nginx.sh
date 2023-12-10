#! /bin/bash

# Dependecy checks
if [[ ! $1 ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
elif [[ $1 != "install" ]] && [[ $1 != "uninstall" ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
fi

if ! which helm &> /dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tHelm is missing!" | tee -a /var/log/k8s-ingress-nginx.log; exit 2; fi

nodes_count=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints|not) | select(.status.conditions[].reason=="KubeletReady" and .status.conditions[].status=="True") | .metadata.name' | wc -l)
if [ ! $nodes_count -gt 0 ]; then
  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tIngress-Nginx setup requires at least 1 node, currently there are ${nodes_count} registered, please enlarge your K8s cluster" | tee -a /var/log/k8s-ingress-nginx.log
  exit 3
fi


# Script variables
CPWD=$(basename $(pwd))
if [ -f $(dirname $0)/values.yaml ]; then
  playground_dir=$(dirname $0)
else
  read -p 'Enter the path to the Playground directory: ' playground_dir
  if [ ! -d $playground_dir ]; then
    echo "Could not validate $playground_dir path"
    exit 2
  fi
fi
namespace='ingress-nginx'

install() {
  # Protect the script from re-run
  if [ ! -f /var/run/ingress-nginx.pid ]; then
    echo $$ > /var/run/ingress-nginx.pid
  else
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tIngress-Nginx setup is already running in the background..." | tee -a /var/log/k8s-ingress-nginx.log
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tUse \`kubectl get events -n ingress-nginx -w\` to check the setup progress..." | tee -a /var/log/k8s-ingress-nginx.log
    exit 4
  fi

  helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ${namespace} --create-namespace \
    -f $playground_dir/values.yaml 1> /dev/null

  kubectl wait --namespace ${namespace} \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s

  if [ -f /etc/cron.d/ingress-nginx-setup ]; then rm -f /etc/cron.d/ingress-nginx-setup; fi
  if [ -f /var/run/ingress-nginx.pid ]; then rm -f /var/run/ingress-nginx.pid; fi
  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tIngress-Nginx installation has been completed" | tee -a /var/log/k8s-ingress-nginx.log
}

uninstall() {
  for ns in $(kubectl get namespace -o json | jq -r '.items[].metadata.name'); do
    if kubectl get ingress -n ${ns} &> /dev/null; then
      for object in $(kubectl get ingress -n ${ns} -o json 2> /dev/null | jq -r '.items[].metadata.name'); do
        kubectl delete -n ${ns} ingress/${object}
      done
    fi
  done
  
  if kubectl get namespace ${namespace} &> /dev/null; then
    helm uninstall ingress-nginx ingress-nginx --namespace ${namespace}
    kubectl delete namespace ${namespace}
  fi
}

$1
