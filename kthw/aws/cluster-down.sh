#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

readonly PROGNAME=$(basename "$0")
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"
readonly ARGS="$@"
readonly TODAY=$(date +%Y%m%d%H%M%S)

# find project root directory using git
readonly PROJECT_ROOT=$(readlink -f $(git rev-parse --show-cdup))

# pull in utils
[[ -f "$PROJECT_ROOT/kthw/utils.sh" ]] && source "$PROJECT_ROOT/kthw/utils.sh"

# pull in gcloud utils
[[ -f "$PROGDIR/gcloud-utils.sh" ]] && source "$PROGDIR/gcloud-utils.sh"

# Defaults for cli arguments
DEFAULT_ZONE=${GKE_ZONE:-'us-central1-c'}
DEFAULT_CLUSTER_NAME=${GKE_CLUSTER_NAME:-'example'}

# cli arguments
ZONE=
CLUSTER_NAME=

usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME deletes a Google Container Engine cluster.

  OPTIONS:
    -c --cluster-name        name of container engine cluster (default: $DEFAULT_CLUSTER_NAME)
    -z --zone                gcp zone (default: $DEFAULT_ZONE)
    -h --help                show this help


  Examples:
    $PROGNAME --cluster-name mystique-dev --zone us-central1-c
EOF
}


cmdline() {
  # got this idea from here:
  # http://kirk.webfinish.com/2009/10/bash-shell-script-to-use-getopts-with-gnu-style-long-positional-parameters/
  local arg=
  local args=
  for arg
  do
    local delim=""
    case "$arg" in
      #translate --gnu-long-options to -g (short options)
      --cluster-name)   args="${args}-c ";;
      --zone)           args="${args}-z ";;
      --help)           args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
          args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- "$args"

  while getopts ":c:z:h" OPTION
  do
     case $OPTION in
     c)
         CLUSTER_NAME=$OPTARG
         ;;
     z)
         ZONE=$OPTARG
         ;;
     h)
         usage
         exit 0
         ;;
     \:)
         echo "  argument missing from -$OPTARG option"
         echo ""
         usage
         exit 1
         ;;
     \?)
         echo "  unknown option: -$OPTARG"
         echo ""
         usage
         exit 1
         ;;
    esac
  done

  return 0
}


valid_args()
{
  ZONE=${ZONE:-"$DEFAULT_ZONE"}
  CLUSTER_NAME=${CLUSTER_NAME:-"$DEFAULT_CLUSTER_NAME"}

  if ! cluster_exists "$CLUSTER_NAME"; then
    error "the gke cluster '$CLUSTER_NAME' doesn't appear to exist."
    exit 1
  fi

  local zone_match=0
  for zone in "${VALID_ZONES[@]}"; do
    if [[ $zone = "$ZONE" ]]; then
        zone_match=1
        break
    fi
  done

  if [[ $zone_match = 0 ]]; then
    error "invalid gce zone.  Refer to the following url for list of valid zones:"
    error "https://cloud.google.com/compute/docs/regions-zones/regions-zones"
    echo ""
    usage
    exit 1
  fi

  # Get region from zone (everything to last dash)
  REGION=$(echo $ZONE | sed "s/-[^-]*$//")
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
}

set_compute_zone()
{
  gcloud config set compute/zone "$ZONE"
  PROJECT_ID=$(gcloud config list project | sed -n 2p | cut -d " " -f 3)
}


cluster_down()
{
  inf ""
  inf "***********************************"
  inf "* Deleting cluster:"
  inf "*   Zone: $ZONE"
  inf "*   Cluster name: $CLUSTER_NAME"
  inf "*   Project ID: $PROJECT_ID"
  inf "***********************************"
  inf ""

  gcloud container clusters delete "$CLUSTER_NAME" -z "$ZONE" -q

  kops delete cluster --state=s3://k8s.mystique.dev.state \ 
    --name=dev.k8s.lowdrag.io \
    --yes
}


delete_disk()
{
  local base_ssd_name="$CLUSTER_NAME-ext-ssd-"
  num_ssds=`gcloud compute disks list | awk -v name="$base_ssd_name" -v zone=$ZONE '$1~name && $2==zone' | wc -l`
  for i in `seq 1 $num_ssds`; do
    gcloud compute disks delete $base_ssd_name$i --zone $ZONE -q
  done
}

main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path $0)"
  cmdline $ARGS
  valid_args
  prerequisites
  set_compute_zone
  cluster_down
  delete_disk
}

[[ "$0" == "$BASH_SOURCE" ]] && main
