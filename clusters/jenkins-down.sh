#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

readonly PROGNAME=$(basename "$0")
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"
readonly ARGS="$@"
readonly TODAY=$(date +%Y%m%d%H%M%S)

# find project root directory using git
readonly PROJECT_ROOT=$(readlink -f $(git rev-parse --show-cdup))

JENKINS_CLUSTER_NAME=${JENKINS_CLUSTER_NAME:-'jenkins'}


gke_cluster_down()
{
  bash -c "$PROJECT_ROOT/kthw/gke/cluster-down.sh --cluster-name $JENKINS_CLUSTER_NAME"
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

  source <(kubectl completion bash)
}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  #prerequisites
  gke_cluster_down
}

[[ "$0" == "$BASH_SOURCE" ]] && main
