#! /bin/bash

# Script variables
if [ -f $(dirname $0)/gitlab-runner-values.yaml ]; then
  playground_dir=$(dirname $0)
else
  read -p 'Enter the path to the Playground directory: ' playground_dir
  if [ ! -d $playground_dir ]; then
    echo "Could not validate $playground_dir path"
    exit 1
  fi
fi

namespace=gitlab-system

# Dependecy checks
if [[ ! $1 ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 2
elif [[ $1 != "install" ]] && [[ $1 != "uninstall" ]]; then
  echo "Please run this script with an argument install||uninstall"
  exit 2
fi

if ! which kubectl &> /dev/null; then echo "Kubectl does not exists, please install it and re-run $0"; exit 1; fi
if [ ! -f $playground_dir/gitlab-runner-values.yaml ]; then
  echo "A configuration file is missing."
  exit 2
fi

if ! kubectl get namespace ${namespace} &> /dev/null; then
  echo 'Gitlab is not installed on this K8s cluster!'
  exit 2
fi
if ! kubectl --namespace ${namespace} get pod -l app.kubernetes.io/instance=gitlab-webservice 2> /dev/null | grep 'Running' &> /dev/null; then
  echo 'Gitlab webservice does not exists'
  exit 2
fi

if ! kubectl -n operators get pod -l app.kubernetes.io/name=gitlab-runner-operator 2> /dev/null | grep 'Running' &> /dev/null; then
  echo 'Gitlab-Runner operator is not running.'
  exit 2
fi

if grep 'namespace: REPLACE_ME' $playground_dir/gitlab-runner-values.yaml &> /dev/null; then
  echo "Please set a NAMESPACE in $playground_dir/gitlab-runner-values.yaml"
  exit 2
fi

if grep 'runner-registration-token: REPLACE_ME' $playground_dir/gitlab-runner-values.yaml &> /dev/null; then
  echo "Please set a RUNNER-REGISTRATION-TOKEN in $playground_dir/gitlab-runner-values.yaml"
  exit 2

fi

install() {
  kubectl apply -f $playground_dir/gitlab-runner-values.yaml
  kubectl apply -f $playground_dir/gitlab-runner.yaml
}

uninstall() {
  kubectl delete -f $playground_dir/gitlab-runner.yaml
  kubectl delete -f $playground_dir/gitlab-runner-values.yaml
}

$1
