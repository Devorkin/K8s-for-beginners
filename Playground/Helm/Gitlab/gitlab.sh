#! /bin/bash

# Dependecy checks
if [[ ! $1 ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
elif [[ $1 != "install" ]] && [[ $1 != "uninstall" ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 1
fi

if ! which kubectl &> /dev/null; then echo "Kubectl does not exists, please install it and re-run $0"; exit 1; fi

# Script variables
if [ -f $(dirname $0)/values.yaml ]; then
  playground_dir=$(dirname $0)
else
  read -p 'Enter the path to the Playground directory: ' playground_dir
  if [ ! -d $playground_dir ]; then
    echo "Could not validate $playground_dir path"
    exit 2
  fi
fi

gitlab_operator_version=0.17.3
gitlab_runner_operator_version=0.24.0
namespace=gitlab-system
platform="kubernetes"

install() {
  kubectl create namespace ${namespace}
  kubectl apply -n ${namespace} -f https://gitlab.com/api/v4/projects/18899486/packages/generic/gitlab-operator/${gitlab_operator_version}/gitlab-operator-${platform}-${gitlab_operator_version}.yaml
  kubectl wait --namespace ${namespace} \
    pod -l control-plane=controller-manager \
    --for condition=Ready \
    --timeout=180s
  
  echo "You can monitor Gitlab installation progress using the command \`kubectl -n ${namespace} logs deployment/gitlab-controller-manager -c manager -f --since=5m\`"
  kubectl -n ${namespace} apply -f ${playground_dir}/values.yaml
  kubectl wait --namespace ${namespace} \
    pod -l app.kubernetes.io/instance=gitlab-webservice \
    --for condition=Ready \
    --timeout=1200s

  # Setup Gitlab Operator Lifecycle Manager (OLM) & the Gitlab-Runner Operator
  if ! kubectl get namespace olm &> /dev/null; then
    curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v${gitlab_runner_operator_version}/install.sh | bash -s v${gitlab_runner_operator_version}
  fi
  if ! kubectl -n operators get pod -l app.kubernetes.io/name=gitlab-runner-operator 2> /dev/null | grep 'Running' &> /dev/null; then
    kubectl create -f https://operatorhub.io/install/gitlab-runner-operator.yaml
    kubectl wait -n operators --for condition=Ready pod -l app.kubernetes.io/name=gitlab-runner-operator --timeout=120s
  fi
}

uninstall() {
  kubectl delete -f https://operatorhub.io/install/gitlab-runner-operator.yaml
  kubectl delete -f https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v${gitlab_runner_operator_version}/olm.yaml
  kubectl delete -f https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v${gitlab_runner_operator_version}/crds.yaml
  kubectl delete namespace operators
  kubectl delete namespace olm
  kubectl -n ${namespace} delete -f ${playground_dir}/values.yaml
  kubectl -n ${namespace} delete -f https://gitlab.com/api/v4/projects/18899486/packages/generic/gitlab-operator/${gitlab_operator_version}/gitlab-operator-${platform}-${gitlab_operator_version}.yaml
  kubectl delete namespace ${namespace}
}

$1
