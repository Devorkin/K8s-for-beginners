#! /bin/bash

# Variables
##### Installation modes:
# Dev: This mode is useful for experimenting with Vault without needing to unseal, It is insecure and will lose data on every restart (since it stores data in-memory).
# HA: This mode uses a highly available backend storage (such as Consul) to store Vault's data.
# Standalone: This mode uses the file storage backend and requires a volume for persistence
#####
INSTALLATION_TYPE='dev'                          # dev||ha||standalone

NAMESPACE='playground'
VAULT_HELM_SETUP_PATH="Helm/Vault"
VAULT_VERSION='0.27.0'
VALUES_FILE_PATH="${VAULT_HELM_SETUP_PATH}/${INSTALLATION_TYPE}-values.yaml"

# Dependecy checks and variables declaration
if [[ ! $1 ]] && [[ $1 != "install" ]] && [[ $1 != "uninstall" ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
fi

for CMD in "helm" "kubectl" "yq"; do
  if ! which $CMD &>/dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\t$CMD is missing!" | tee -a /var/log/k8s-vault.log; exit 1; fi
done

# Checking if the Helm custom values.yaml file is accessible
CPWD=$(basename $(pwd))
if [[ $CPWD == "K8s-for-beginners" ]] || [[ $CPWD == "vagrant" ]]; then
  playground_dir="./Playground"
elif [ -f ${VALUES_FILE_PATH} ]; then
    playground_dir="."
elif [ ! -z $2 ]; then
    playground_dir=$2
else
  read -p 'Enter the path to the Playground directory: ' playground_dir
fi
if [ ! -f $playground_dir/${VALUES_FILE_PATH} ]; then
  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tCould not validate $playground_dir path" | tee -a /var/log/k8s-vault.log
  exit 4
fi


install () {
  if [ $INSTALLATION_TYPE == 'ha' ]; then
    nodes_count=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints|not) | select(.status.conditions[].reason=="KubeletReady" and .status.conditions[].status=="True") | .metadata.name' | wc -l)
    if [ ! $nodes_count -gt 2 ]; then
      echo -e "`date +"%d-%m-%y %H:%M:%S"`\tVault cluster requires at least 3 nodes, currently there are ${nodes_count} registered, please enlarge your K8s cluster" | tee -a /var/log/k8s-vault.log
      exit 3
    fi
  elif [ $INSTALLATION_TYPE == 'standalone' ]; then
    if ! kubectl get pv/vault-pv &> /dev/null; then
      kubectl apply -f $playground_dir/${VAULT_HELM_SETUP_PATH}/pv.yaml
      sleep 5
    fi
  fi

  helm repo add hashicorp https://helm.releases.hashicorp.com
  helm install \
    --namespace ${NAMESPACE} \
    vault hashicorp/vault \
    --version ${VAULT_VERSION} \
    -f $playground_dir/${VALUES_FILE_PATH}

  while ! kubectl wait -n ${NAMESPACE} pod -l app.kubernetes.io/name=vault --for=jsonpath='{.status.phase}'=Running --timeout=120s 2> /dev/null; do sleep 5; done

  if [ $INSTALLATION_TYPE == 'ha' ] || [ $INSTALLATION_TYPE == 'standalone' ]; then
    FIRST_POD=$(kubectl -n ${NAMESPACE} get pod -l app.kubernetes.io/name=vault -o json | jq -r '.items[].metadata.name' | head -n 1)
    VAULT_INIT_DATA=$(kubectl exec -n ${NAMESPACE} ${FIRST_POD} -- vault operator init -key-shares=1 -key-threshold=1 -format=json)
    VAULT_TOKEN=$(echo ${VAULT_INIT_DATA} | jq -r ".root_token")
    VAULT_UNSEAL_KEY=$(echo ${VAULT_INIT_DATA} | jq -r ".unseal_keys_b64[]")

    kubectl exec -n ${NAMESPACE} ${FIRST_POD} -- vault operator unseal ${VAULT_UNSEAL_KEY} &> /dev/null
  fi
  
  if [ $INSTALLATION_TYPE == 'ha' ]; then
    for POD in $(kubectl get -n ${NAMESPACE} pod -l app.kubernetes.io/name=vault -o json | jq -r '.items[].metadata.name'); do
      if [[ ${POD} != ${FIRST_POD} ]]; then
        kubectl exec -n ${NAMESPACE} ${POD} -- vault operator raft join http://${FIRST_POD}.vault-internal:8200 &> /dev/null
        kubectl exec -n ${NAMESPACE} ${POD} -- vault operator unseal ${VAULT_UNSEAL_KEY} &> /dev/null
      fi
    done

    # Check Raft list peers
    kubectl exec -n ${NAMESPACE} ${FIRST_POD} -- env VAULT_TOKEN=${VAULT_TOKEN} vault operator raft list-peers
  fi

  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tVault has been successfully installed, via ${INSTALLATION_TYPE} mode!" | tee -a /var/log/k8s-vault.log
  if [ $INSTALLATION_TYPE == 'ha' ] || [ $INSTALLATION_TYPE == 'standalone' ]; then
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tVault UNSEAL KEY: ${VAULT_UNSEAL_KEY}" | tee -a /var/log/k8s-vault.log
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tVault TOKEN: ${VAULT_TOKEN}" | tee -a /var/log/k8s-vault.log
  fi
}

uninstall () {
  if kubectl get -n ${NAMESPACE} StatefulSet vault &> /dev/null; then
    helm uninstall vault --namespace ${NAMESPACE}
  fi

  for PVC in $(kubectl -n ${NAMESPACE} get pvc -o=custom-columns=NAME:.metadata.name --no-headers | grep vault); do
    if kubectl get -n ${NAMESPACE} pvc/${PVC} &> /dev/null; then
      kubectl delete -n ${NAMESPACE} pvc/${PVC} &> /dev/null
    fi
  done

  if [ $INSTALLATION_TYPE == 'standalone' ]; then
    if kubectl get pv/vault-audit-pv &> /dev/null; then
      kubectl delete -f $playground_dir/${VAULT_HELM_SETUP_PATH}/pv.yaml &> /dev/null
    fi
  fi

  kubectl delete -n ${NAMESPACE} ingress/vault 2> /dev/null
}

$1
