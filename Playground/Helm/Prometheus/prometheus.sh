#! /bin/bash

BASE_DIR="$(dirname "${BASH_SOURCE[0]}")"
HELM_REPO='prometheus-community/kube-prometheus-stack'
NAMESPACE='playground'    # Replace with 'monitoring' instead

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

if ! which helm &>/dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tHelm is missing!" | tee -a /var/log/k8s-prometheus.log; exit 1; fi
if ! which kubectl &>/dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tKubectl is missing!" | tee -a /var/log/k8s-prometheus.log; exit 2; fi

# Checking if the Helm custom values.yaml file is accessible
if [ ! -f ${VALUES_FILE_PATH} ]; then
  echo "${VALUES_FILE_PATH}"
  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tCould not validate ${VALUES_FILE_PATH} path" | tee -a /var/log/k8s-prometheus.log
  exit 3
fi


install () {
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

  helm install \
    --namespace ${NAMESPACE} \
    prometheus ${HELM_REPO}
    -f ${VALUES_FILE_PATH}
}

uninstall () {
  helm uninstall prometheus --namespace ${NAMESPACE}

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
  helm upgrade -f ${VALUES_FILE_PATH} prometheus ${HELM_REPO} --install
}

$1