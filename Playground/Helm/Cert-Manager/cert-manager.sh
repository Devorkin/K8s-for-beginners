#! /bin/bash
set -e

# Dependecy checks
if [[ ! $1 ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
elif [[ $1 != "install" ]] && [[ $1 != "uninstall" ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
fi

if ! which base64 &> /dev/null; then echo "Helm does not exists, please install it and re-run $0"; exit 1; fi
if ! which helm &> /dev/null; then echo "Helm does not exists, please install it and re-run $0"; exit 1; fi
if ! which kubectl &> /dev/null; then echo "Kubectl does not exists, please install it and re-run $0"; exit 1; fi
if ! which openssl &> /dev/null; then echo "OpenSSL does not exists, please install it and re-run $0"; exit 1; fi

# Variables
CA_NAME='k8s-playground-ca'
NAMESPACE='cert-manager'

install() {
  helm upgrade --install cert-manager cert-manager \
    --repo https://charts.jetstack.io \
    --create-namespace \
    --namespace ${NAMESPACE} \
    --set installCRDs=true
  kubectl wait -n ${NAMESPACE} pod -l app.kubernetes.io/name=cert-manager --for condition=Ready --timeout=60s

  if ! kubectl -n ssl-ready get secret/${CA_NAME}-secret > /dev/null 2>&1 && ! kubectl -n ${NAMESPACE} get secret/${CA_NAME}-secret > /dev/null 2>&1; then
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
  elif kubectl -n ssl-ready get secret/${CA_NAME}-secret > /dev/null 2>&1 && ! kubectl -n ${NAMESPACE} get secret/${CA_NAME}-secret > /dev/null 2>&1; then
  CRT_DATA=`kubectl -n ssl-ready get secret/${CA_NAME} -o jsonpath='{.data.tls\.crt}'`
  KEY_DATA=`kubectl -n ssl-ready get secret/${CA_NAME} -o jsonpath='{.data.tls\.key}'`
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${CA_NAME}
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
  kubectl wait ClusterIssuer ${CA_NAME}-issuer --for condition=Ready --timeout=60s

  echo "1st note: Make sure you distribute the new CA autorithy certificate to all cluster nodes"
  echo "2nd note: Make sure you distribute the new CA autorithy certificate to all systems\applications that may require access to services signed by this ROOT CA"
}

uninstall() {
  kubectl delete ClusterIssuer/${CA_NAME}-issuer
  kubectl delete -n ${NAMESPACE} Secret/${CA_NAME}-secret
  helm uninstall cert-manager cert-manager --namespace ${NAMESPACE}
  kubectl delete ns ${NAMESPACE}

  echo "1st note: Please remove this CA autorithy certificate from all cluster nodes"
  echo "2nd note: Please remove this CA autorithy certificate from all systems\applications that required access to services signed by that ROOT CA"
}

$1
exit 0