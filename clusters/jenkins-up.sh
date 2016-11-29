#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

readonly PROGNAME=$(basename "$0")
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"
readonly ARGS="$@"
readonly TODAY=$(date +%Y%m%d%H%M%S)

# find project root directory using git
readonly PROJECT_ROOT=$(readlink -f $(git rev-parse --show-cdup))

JENKINS_CLUSTER_NAME=${JENKINS_CLUSTER_NAME:-'jenkins'}
JENKINS_NUM_NODES=${JENKINS_NUM_NODES:-'5'}
JENKINS_NAMESPACE=${JENKINS_NAMESPACE:-'jenkins'}
JENKINS_CERTS_SECRET=${JENKINS_CERTS_SECRET:-'testcerts'}

# pull in utils
[[ -f "$PROJECT_ROOT/kthw/utils.sh" ]] && source "$PROJECT_ROOT/kthw/utils.sh"


gke_cluster_up()
{
  bash -c "$PROJECT_ROOT/kthw/gke/cluster-up.sh --cluster-name $JENKINS_CLUSTER_NAME --num-nodes $JENKINS_NUM_NODES --alpha"

  kubectl cluster-info 2>/dev/null
  if [ $? -ne 0 ]; then
    error ""
    error "Cluster \"$JENKINS_CLUSTER_NAME\" was not created"
    exit 1
  fi
}

create_namespace()
{
  #bash -c "kubectl create ns "JENKINS_NAMESPACE"
  kubectl create ns "$JENKINS_NAMESPACE"

  kubectl get ns jenkins 2>/dev/null
  if [ $? -ne 0 ]; then
    error ""
    error "Namespace \"$JENKINS_NAMESPACE\" was not created"
    exit 1
  fi
}

create_test_certs()
{
  local certs_dir="/tmp/test-cluster/certs"
  rm -rf "$certs_dir"
  mkdir -p "$certs_dir"
  bash -c "export CERTS_OUTPUT_DIR=$certs_dir; $PROJECT_ROOT/cfssl/generate.sh"

  local secrets_dir="/tmp/test-cluster/secrets"
  rm -rf "$secrets_dir"
  mkdir -p "$secrets_dir"
  mv "$certs_dir/intermediate_ca.pem" "$secrets_dir/ca-cert.pem"
  mv "$certs_dir/cert.pem" "$secrets_dir/cert.pem"
  mv "$certs_dir/cert-key.pem" "$secrets_dir/cert-key.pem"
  mv "$certs_dir/client.pem" "$secrets_dir/client.pem"
  mv "$certs_dir/client-key.pem" "$secrets_dir/client-key.pem"

  kubectl create secret generic "$JENKINS_CERTS_SECRET" --from-file="$secrets_dir" --namespace="$JENKINS_NAMESPACE"
}

helm_init()
{
  helm init
  inf ""
  inf "will sleep for 60 seconds to allow helm to deploy to kubernetes cluster"
  sleep 60s
  kubectl get pods --namespace kube-system | grep "tiller"
}

install_jenkins()
{
  helm install "$PROJECT_ROOT/charts/jenkins" --name cicd --namespace="$JENKINS_NAMESPACE"
}

# Make sure we have all the right stuff
prerequisites() {
  if ! command_exists gcloud; then
    error "gcloud does not appear to be installed. Please install and re-run this script."
    exit 1
  fi

  if ! command_exists kubectl; then
    error "kubectl does not appear to be installed. Please install and re-run this script."
    exit 1
  fi

  if ! command_exists helm; then
    error "helm does not appear to be installed. Please install and re-run this script."
    exit 1
  fi

  source <(kubectl completion bash)
}

main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path "$0")"
  prerequisites

  gke_cluster_up
  create_namespace
  create_test_certs
  helm_init
  install_jenkins
}

[[ "$0" == "$BASH_SOURCE" ]] && main
