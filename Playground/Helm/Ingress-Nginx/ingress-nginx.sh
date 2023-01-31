#! /bin/bash

if ! which helm &> /dev/null; then echo "Helm does not exists, please install it and re-run $0"; exit 1; fi

# Script variables
CPWD=$(basename $(pwd))
if [ -f values.yaml ]; then
  playground_dir="."
elif [[ $CPWD == "K8s-for-begginers" ]]; then
  playground_dir="./Playground/Helm/Ingress-Nginx"
else
  read -p 'Enter the path to the Playground directory: ' playground_dir
  if [ ! -d $playground_dir ]; then
    echo "Could not validate $playground_dir path"
    exit 2
  fi
fi

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f $playground_dir/values.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
