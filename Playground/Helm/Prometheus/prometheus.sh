#! /bin/bash
# set -x

BASE_DIR="$(dirname "${BASH_SOURCE[0]}")"
HELM_REPO='prometheus-community/kube-prometheus-stack'
NAMESPACE='monitoring'

if [[ ${PROVISION_CEPH} == "true" ]]; then
  VALUES_FILE_PATH="${BASE_DIR}/values-with-block-storage.yaml"
else
  VALUES_FILE_PATH="${BASE_DIR}/values-with-local-storage.yaml"
fi

# Dependecy checks and variables declaration
if [[ ! $1 ]]; then
  echo "Please run this script with an argument install||uninstall||update"
  exit 1
elif [[ $1 != "install" ]] && [[ $1 != "update" ]] && [[ $1 != "uninstall" ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 2
fi

if ! which helm &>/dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tHelm is missing!" | tee -a /var/log/k8s-prometheus.log; exit 3; fi
if ! which kubectl &>/dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tKubectl is missing!" | tee -a /var/log/k8s-prometheus.log; exit 4; fi

# Checking if the Helm custom values.yaml file is accessible
if [ ! -f ${VALUES_FILE_PATH} ]; then
  echo "${VALUES_FILE_PATH}"
  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tCould not validate ${VALUES_FILE_PATH} path" | tee -a /var/log/k8s-prometheus.log
  exit 5
fi

if [[ ${PROVISION_CEPH} == "true" ]]; then
  nodes_count=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints|not) | select(.status.conditions[].reason=="KubeletReady" and .status.conditions[].status=="True") | .metadata.name' | wc -l)
  if [ $nodes_count -lt 4 ]; then
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\Prometheus setup requires at least 3 nodes, currently there are ${nodes_count} nodes registered, please enlarge your K8s cluster" | tee -a /var/log/k8s-prometheus.log
    exit 6
  fi
fi

install () {
  # Protect the script from re-run
  if [ ! -f /var/run/prometheus.pid ]; then
    echo $$ > /var/run/prometheus.pid
  else
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tPrometheus setup is already running in the background..." | tee -a /var/log/k8s-prometheus.log
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tUse \`kubectl get events -n ${NAMESPACE} -w\` to check the setup progress..." | tee -a /var/log/k8s-prometheus.log
    exit 7
  fi

  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

  helm install --atomic --create-namespace \
    --namespace ${NAMESPACE} \
    prometheus ${HELM_REPO} \
    -f ${VALUES_FILE_PATH}

  if [ -f /etc/cron.d/prometheus-setup ]; then rm -f /etc/cron.d/prometheus-setup; fi
  if [ -f /var/run/prometheus.pid ]; then rm -f /var/run/prometheus.pid; fi
}

uninstall () {
  helm uninstall prometheus --namespace ${NAMESPACE}

  for JOB in $(kubectl get jobs -n ${NAMESPACE} -l app.kubernetes.io/instance=prometheus -o json 2> /dev/null | jq -r '.items[].metadata.name'); do
    kubectl -n ${NAMESPACE} delete job/${JOB}
  done

  for POD in $(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=prometheus -o json 2> /dev/null | jq -r '.items[].metadata.name'); do
    kubectl -n ${NAMESPACE} delete pod/${POD}
  done

  for CRD in 'alertmanagerconfigs.monitoring.coreos.com' \
              'alertmanagers.monitoring.coreos.com' \
              'podmonitors.monitoring.coreos.com' \
              'probes.monitoring.coreos.com' \
              'prometheusagents.monitoring.coreos.com' \
              'prometheuses.monitoring.coreos.com' \
              'prometheusrules.monitoring.coreos.com' \
              'scrapeconfigs.monitoring.coreos.com' \
              'servicemonitors.monitoring.coreos.com' \
              'thanosrulers.monitoring.coreos.com'; do
    kubectl delete crd ${CRD}
  done
}

update () {
  helm upgrade --namespace ${NAMESPACE} \
    prometheus ${HELM_REPO} \
    -f ${VALUES_FILE_PATH} \
    --install
}

$1