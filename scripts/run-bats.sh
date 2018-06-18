#!/usr/bin/env bash

set -e

context="$(kubectl config current-context)"

# Change the current-context to minikube
kubectl config use-context minikube

for bats_file in $(find test -name "*.bats"); do
  echo "=> $bats_file"
  bats "$bats_file"
done

if [[ "$context" != "minikube" ]]; then
  echo "Restore the current-context to $context"
  kubectl config use-context "$context"
fi
