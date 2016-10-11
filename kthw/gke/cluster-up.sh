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

# pull in kubectl utils
[[ -f "$PROJECT_ROOT/kthw/kubectl-utils.sh" ]] && source "$PROJECT_ROOT/kthw/kubectl-utils.sh"

# pull in gcloud utils
[[ -f "$PROGDIR/gcloud-utils.sh" ]] && source "$PROGDIR/gcloud-utils.sh"

# Defaults for cli arguments
DEFAULT_ZONE=${GKE_ZONE:-'us-central1-c'}
DEFAULT_MACHINE_TYPE=${GKE_MACHINE_TYPE:-'n1-standard-4'}
DEFAULT_CLUSTER_NAME=${GKE_CLUSTER_NAME:-'example'}
DEFAULT_SSD_SIZE_GB=${GKE_SSD_SIZE_GB:-0}
DEFAULT_NUM_NODES=${GKE_NUM_NODES:-0}
DATAROOT_VOLUME=${GKE_DATAROOT_VOLUME:-'/ssd'}
NUM_LOCAL_SSD=${GKE_NUM_LOCAL_SSD:-1}

# cli arguments
ZONE=
MACHINE_TYPE=
CLUSTER_NAME=
SSD_SIZE_GB=
NUM_NODES=
PASSWORD=
ENABLE_ALPHA=1

usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME creates a Google Container Engine cluster.

  OPTIONS:
    -c --cluster-name        name of container engine cluster (default: $DEFAULT_CLUSTER_NAME)
    -n --num-nodes           number of cluster nodes (default: $DEFAULT_NUM_NODES)
    -m --machine-type        gcp machine type (default: $DEFAULT_MACHINE_TYPE)
    -s --ssd-size            external ssd disk size in GB (default: $DEFAULT_SSD_SIZE_GB)
    -z --zone                gcp zone (default: $DEFAULT_ZONE)
    -p --password            cluster password
    -a --alpha               enable Kubernetes alpha features (default: disabled)
    -h --help                show this help


  Examples:
    $PROGNAME --cluster-name mystique-dev --num-nodes 5
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
      --num-nodes)      args="${args}-n ";;
      --machine-type)   args="${args}-m ";;
      --password)       args="${args}-p ";;
      --ssd-size)       args="${args}-s ";;
      --zone)           args="${args}-z ";;
      --alpha)          args="${args}-a ";;
      --help)           args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
          args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- "$args"

  while getopts ":c:n:m:p:s:z:ah" OPTION
  do
     case $OPTION in
     c)
         CLUSTER_NAME=$OPTARG
         ;;
     n)
         NUM_NODES=$OPTARG
         ;;
     m)
         MACHINE_TYPE=$OPTARG
         ;;
     p)
         PASSWORD=$OPTARG
         ;;
     s)
         SSD_SIZE_GB=$OPTARG
         ;;
     z)
         ZONE=$OPTARG
         ;;
     a)
	 ENABLE_ALPHA=0
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
  MACHINE_TYPE=${MACHINE_TYPE:-"$DEFAULT_MACHINE_TYPE"}
  CLUSTER_NAME=${CLUSTER_NAME:-"$DEFAULT_CLUSTER_NAME"}
  SSD_SIZE_GB=${SSD_SIZE_GB:-"$DEFAULT_SSD_SIZE_GB"}
  NUM_NODES=${NUM_NODES:-"$DEFAULT_NUM_NODES"}

  if cluster_exists "$CLUSTER_NAME"; then
    error "the gke cluster '$CLUSTER_NAME' already exists."
    exit 1
  fi

  local number_re='^[0-9]+$'
  if ! [[ $NUM_NODES =~ $number_re ]] ; then
    error "number of nodes must be a numeric value"
    echo ""
    usage
    exit 1
  fi

  if ! [[ $SSD_SIZE_GB =~ $number_re ]] ; then
    error "number of nodes must be a numeric value"
    echo ""
    usage
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


cluster_up()
{
  inf ""
  inf "****************************************"
  inf "* Creating cluster:"
  inf "*   Project ID: $PROJECT_ID"
  inf "*   Zone: $ZONE"
  inf "*   Cluster name: $CLUSTER_NAME"
  inf "*   Machine type: $MACHINE_TYPE"
  inf "*   Num of nodes: $NUM_NODES"
  inf "*   External SSD size: $SSD_SIZE_GB"
  inf "*   Num of local (375GB) SSD disk(s): $NUM_LOCAL_SSD"
  if [ "$ENABLE_ALPHA" -eq 0 ]; then
    inf "*   Alpha features: enabled"
  else 
    inf "*   Alpha features: disabled"
  fi
  inf "****************************************"
  inf ""

  # options for how cluster is created
  local cluster_options
  cluster_options="--machine-type $MACHINE_TYPE --num-nodes $NUM_NODES --scopes storage-rw"

  cluster_options="$cluster_options,service-control,logging-write,datastore,sql,sql-admin,bigquery"

  if [ "$NUM_LOCAL_SSD" -gt 0 ]; then
    cluster_options="$cluster_options --local-ssd-count=$NUM_LOCAL_SSD"
  fi

  if [ -n "$PASSWORD" ]; then
    cluster_options="$cluster_options --password $PASSWORD"
  fi
 
  if [ "$ENABLE_ALPHA" -eq 0 ]; then
    cluster_options="$cluster_options --enable-kubernetes-alpha"
  fi

  gcloud container clusters create "$CLUSTER_NAME" $(echo "$cluster_options")
}


create_kubectl_config()
{
  inf ""
  inf ""
  inf "Creating kubectl config..."

  rm "$HOME/.kube/config"
  gcloud config set container/cluster "$CLUSTER_NAME"
  gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE"
}


attach_disk()
{
  inf ""
  inf ""
  inf "Creating SSDs and attaching to container engine nodes..."

  local kubectl_cmd
  kubectl_cmd=$(which kubectl)

  i=1
  for nodename in $($kubectl_cmd get nodes --no-headers | awk '{print $1}'); do
    diskname="$CLUSTER_NAME-ext-ssd-$i"
    gcloud compute disks create "$diskname" --type=pd-ssd --size="${SSD_SIZE_GB}GB"
    gcloud compute instances attach-disk "$nodename" --disk "$diskname"
    gcloud compute ssh "$nodename" --zone="$ZONE" --command "sudo mkdir ${DATAROOT_VOLUME}; sudo /usr/share/google/safe_format_and_mount -m \"mkfs.ext4 -o noatime -F\" /dev/disk/by-id/google-persistent-disk-1 ${DATAROOT_VOLUME} &"
    gcloud compute ssh "$nodename" --zone="$ZONE" --command "echo '/dev/disk/by-id/google-persistent-disk-1 /ssd ext4 defaults,noatime 0 0' | sudo tee --append /etc/fstab > /dev/null"
    let i=i+1
  done
}


dump_cluster_status() {
  component_status
  cluster_info
  get_nodes

  local cluster_password=$(gcloud container clusters describe "$CLUSTER_NAME" | grep password | awk -F' ' '{print $2}')

  inf ""
  inf "Cluster Password: $cluster_password"
  inf ""
  inf ""
}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path "$0")"
  cmdline $ARGS
  valid_args
  prerequisites
  set_compute_zone
  cluster_up
  create_kubectl_config

  # Creating SSDs and attach to container engine nodes
  if [ "$SSD_SIZE_GB" -gt 0 ]; then
    attach_disk
  fi

  dump_cluster_status
}

[[ "$0" == "$BASH_SOURCE" ]] && main
