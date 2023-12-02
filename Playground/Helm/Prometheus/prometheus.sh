#! /bin/bash

BASE_DIR="$(dirname "${BASH_SOURCE[0]}")"
HELM_REPO='prometheus-community/kube-prometheus-stack'
NAMESPACE='monitoring'

if [ -f /var/lock/rook-ceph.lck ]; then
  VALUES_FILE_PATH="${BASE_DIR}/values-with-block-storage.yaml"
else
  VALUES_FILE_PATH="${BASE_DIR}/values-with-local-storage.yaml"
fi

# Dependecy checks and variables declaration
if [ ! $1 ]; then
  echo "Please run this script with an argument install||uninstall||update"
  exit 1
elif [ $1 != "install" ] && [ $1 != "update" ] && [ $1 != "uninstall" ]; then
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

if [ -f /var/lock/rook-ceph.lck ]; then
  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tRook-Ceph setup has not been completed yet, this dependecy must be validated first!" | tee -a /var/log/k8s-prometheus.log
  exit 6
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
    -f ${VALUES_FILE_PATH} | tee -a /var/log/k8s-prometheus.log

  if [ -f /etc/cron.d/prometheus-setup ]; then rm -f /etc/cron.d/prometheus-setup; fi
  if [ -f /var/run/prometheus.pid ]; then rm -f /var/run/prometheus.pid; fi
}

uninstall () {
  helm uninstall prometheus --namespace ${NAMESPACE} | tee -a /var/log/k8s-prometheus.log

  for JOB in $(kubectl get jobs -n ${NAMESPACE} -l app.kubernetes.io/instance=prometheus -o json 2> /dev/null | jq -r '.items[].metadata.name'); do
    kubectl -n ${NAMESPACE} delete job/${JOB} | tee -a /var/log/k8s-prometheus.log
  done

  for POD in $(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=prometheus -o json 2> /dev/null | jq -r '.items[].metadata.name'); do
    kubectl -n ${NAMESPACE} delete pod/${POD} | tee -a /var/log/k8s-prometheus.log
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
    kubectl delete crd ${CRD} | tee -a /var/log/k8s-prometheus.log
  done
}

update () {
  helm upgrade --namespace ${NAMESPACE} \
    prometheus ${HELM_REPO} \
    -f ${VALUES_FILE_PATH} \
    --install | tee -a /var/log/k8s-prometheus.log
}

$1