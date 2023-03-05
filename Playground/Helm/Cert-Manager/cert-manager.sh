#! /bin/bash

# Dependecy checks
if [[ ! $1 ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
elif [[ $1 != "install" ]] && [[ $1 != "uninstall" ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
fi

if ! which base64 &> /dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tBase64 is missing!" | tee -a /var/log/cert-manager.log; exit 2; fi
if ! which helm &> /dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tHelm is missing!" | tee -a /var/log/cert-manager.log; exit 2; fi
if ! which kubectl &> /dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tKubectl is missing!" | tee -a /var/log/cert-manager.log; exit 2; fi
if ! which openssl &> /dev/null; then echo -e "`date +"%d-%m-%y %H:%M:%S"`\tOpenSSL is missing!" | tee -a /var/log/cert-manager.log; exit 2; fi

NODES_COUNT=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints|not) | select(.status.conditions[].reason=="KubeletReady" and .status.conditions[].status=="True") | .metadata.name' | wc -l)
if [ ! $NODES_COUNT -gt 0 ]; then
  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tCert-Manager setup requires at least 1 node, currently there are ${NODES_COUNT} registered, please enlarge your K8s cluster" | tee -a /var/log/cert-manager.log
  exit 3
fi

# Variables
CA_NAME='k8s-playground-ca'
NAMESPACE='cert-manager'

install() {
  # Protect the script from re-run
  if [ ! -f /var/run/cert-manager.pid ]; then
    echo $$ > /var/run/cert-manager.pid
  else
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tCert-Manager setup is already running in the background..." | tee -a /var/log/cert-manager.log
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tUse \`kubectl get events -n cert-manager -w\` to check the setup progress..." | tee -a /var/log/cert-manager.log
    exit 4
  fi

  echo -e "`date +"%d-%m-%y %H:%M:%S"`\tInstalling Cert-Manager from Helm..." | tee -a /var/log/cert-manager.log
  helm upgrade --install cert-manager cert-manager \
    --repo https://charts.jetstack.io \
    --create-namespace \
    --namespace ${NAMESPACE} \
    --set installCRDs=true
  kubectl wait -n ${NAMESPACE} pod -l app.kubernetes.io/name=cert-manager --for condition=Ready --timeout=60s

  if ! kubectl -n ssl-ready get secret/${CA_NAME}-secret &> /dev/null && ! kubectl -n ${NAMESPACE} get secret/${CA_NAME}-secret &> /dev/null; then
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tGenerating self-Signed CA autority certificate..." | tee -a /var/log/cert-manager.log
    CA_LIFE_TIME='3650'
    ROOT_CA_PATH='root-ca'
    
    if [ ! -d ./${ROOT_CA_PATH} ]; then
      mkdir ${ROOT_CA_PATH}
    fi
  
    openssl genrsa -out ./${ROOT_CA_PATH}/root-ca.key 4096
    openssl req -x509 -new -nodes -key ${ROOT_CA_PATH}/root-ca.key -days ${CA_LIFE_TIME} -sha256 -out ${ROOT_CA_PATH}/root-ca.crt -subj "/CN=${CA_NAME}"
    cp /etc/pki/tls/certs/${CA_NAME}.crt /usr/local/share/ca-certificates/
    update-ca-certificates

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${CA_NAME}-secret
  namespace: ${NAMESPACE}
type: Opaque
data:
  tls.crt: $(cat ${ROOT_CA_PATH}/root-ca.crt | base64 -w 0)
  tls.key: $(cat ${ROOT_CA_PATH}/root-ca.key | base64 -w 0)
EOF

  elif kubectl -n ssl-ready get secret/${CA_NAME}-secret &> /dev/null && ! kubectl -n ${NAMESPACE} get secret/${CA_NAME}-secret &> /dev/null; then
    echo -e "`date +"%d-%m-%y %H:%M:%S"`\tImporting an already existing CA autority certificate..." | tee -a /var/log/cert-manager.log
  CRT_DATA=`kubectl -n ssl-ready get secret/${CA_NAME}-secret -o jsonpath='{.data.tls\.crt}'`
  KEY_DATA=`kubectl -n ssl-ready get secret/${CA_NAME}-secret -o jsonpath='{.data.tls\.key}'`
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${CA_NAME}-secret
  namespace: ${NAMESPACE}
type: Opaque
data:
  tls.crt: ${CRT_DATA}
  tls.key: ${KEY_DATA}
EOF
  fi

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${CA_NAME}-issuer
spec:
  ca:
    secretName: ${CA_NAME}-secret
EOF

  echo "1st note: Make sure you distribute the new CA autorithy certificate to all cluster nodes"
  echo "2nd note: Make sure you distribute the new CA autorithy certificate to all systems\applications that may require access to services signed by this ROOT CA"

  if [ -f /etc/cron.d/cert-manager-setup ]; then rm -f /etc/cron.d/cert-manager-setup; fi
  if [ -f /var/run/cert-manager.pid ]; then rm -f /var/run/cert-manager.pid; fi
}

uninstall() {
  if kubectl get ClusterIssuer/${CA_NAME}-issuer &> /dev/null; then kubectl delete ClusterIssuer/${CA_NAME}-issuer; fi
  if kubectl get -n ${NAMESPACE} Secret/${CA_NAME}-secret &> /dev/null; then kubectl delete -n ${NAMESPACE} Secret/${CA_NAME}-secret; fi
  if kubectl get ns ${NAMESPACE} &> /dev/null; then helm uninstall cert-manager cert-manager --namespace ${NAMESPACE}; fi
  kubectl delete ns ${NAMESPACE}

  echo "1st note: Please remove this CA autorithy certificate from all cluster nodes"
  echo "2nd note: Please remove this CA autorithy certificate from all systems\applications that required access to services signed by that ROOT CA"
}

$1
exit 0