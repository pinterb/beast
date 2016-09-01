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

# pull in aws utils
[[ -f "$PROGDIR/aws-utils.sh" ]] && source "$PROGDIR/aws-utils.sh"

# Defaults for cli arguments
##export AWS_SECURITY_GROUP="docker-machine"
##export AWS_INSTANCE_TYPE="t2.micro"
##export AWS_ROOT_SIZE="16"

DEFAULT_NODE_TYPE=${AWS_K8S_NODE_TYPE:-'t2.medium'}
DEFAULT_MASTER_TYPE=${AWS_K8S_MASTER_TYPE:-'m3.large'}
DEFAULT_CLUSTER_NAME=${AWS_K8S_CLUSTER_NAME:-'dev.k8s'}
DEFAULT_DOMAIN_NAME=${AWS_DEFAULT_ROUTE53_DOMAIN:-'lowdrag.io'}

DEFAULT_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
DEFAULT_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
DEFAULT_STATE_STORE=${AWS_DEFAULT_S3_BUCKET:-'k8s.mystique.dev.state'}
DEFAULT_REGION=${AWS_DEFAULT_REGION:-'us-east-1'}
DEFAULT_ZONE=${AWS_ZONE:-'c'}

##DEFAULT_SSD_SIZE_GB=${GKE_SSD_SIZE_GB:-0}
DEFAULT_NUM_NODES=${AWS_DEFAULT_K8S_NUM_NODES:-2}
##DATAROOT_VOLUME=${GKE_DATAROOT_VOLUME:-'/ssd'}
####NUM_LOCAL_SSD=${GKE_NUM_LOCAL_SSD:-1}

# cli arguments
ZONE=
NODE_TYPE=
MASTER_TYPE=
CLUSTER_NAME=
SSD_SIZE_GB=
NUM_NODES=
S3_STATE_STORE=

usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME creates a Kubernetes cluster on AWS using the kops cli utility.

  OPTIONS:
    -c --cluster-name        name of container engine cluster (default: ${DEFAULT_CLUSTER_NAME}.${DEFAULT_DOMAIN_NAME})
    -n --num-nodes           number of cluster nodes (default: $DEFAULT_NUM_NODES)
    -s --state-store         aws s3 bucket used for cluster state storage (default: $DEFAULT_STATE_STORE)
    -t --node-type           aws ec2 instance type for k8s node (default: $DEFAULT_NODE_TYPE)
    -x --master-type         aws ec2 instance type for k8s master (default: $DEFAULT_MASTER_TYPE)
    -z --zone                aws zone (default: ${DEFAULT_REGION}${DEFAULT_ZONE})
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
      --node-type)      args="${args}-t ";;
      --master-type)    args="${args}-x ";;
      --state-store)    args="${args}-s ";;
      --zone)           args="${args}-z ";;
      --help)           args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
          args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- "$args"

  while getopts ":c:n:t:x:s:z:h" OPTION
  do
     case $OPTION in
     c)
         CLUSTER_NAME=$OPTARG
         ;;
     n)
         NUM_NODES=$OPTARG
         ;;
     t)
         NODE_TYPE=$OPTARG
         ;;
     x)
         MASTER_TYPE=$OPTARG
         ;;
     s)
         S3_STATE_STORE=$OPTARG
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
  ZONE=${ZONE:-"${DEFAULT_REGION}${DEFAULT_ZONE}"}
  NODE_TYPE=${NODE_TYPE:-"$DEFAULT_NODE_TYPE"}
  MASTER_TYPE=${MASTER_TYPE:-"$DEFAULT_MASTER_TYPE"}
  CLUSTER_NAME=${CLUSTER_NAME:-"${DEFAULT_CLUSTER_NAME}.${DEFAULT_DOMAIN_NAME}"}
  S3_STATE_STORE=${S3_STATE_STORE:-"$DEFAULT_STATE_STORE"}
##  SSD_SIZE_GB=${SSD_SIZE_GB:-"$DEFAULT_SSD_SIZE_GB"}
  NUM_NODES=${NUM_NODES:-"$DEFAULT_NUM_NODES"}

##  if cluster_exists "$CLUSTER_NAME"; then
##    error "the gke cluster '$CLUSTER_NAME' already exists."
##    exit 1
##  fi
##
##  local number_re='^[0-9]+$'
##  if ! [[ $NUM_NODES =~ $number_re ]] ; then
##    error "number of nodes must be a numeric value"
##    echo ""
##    usage
##    exit 1
##  fi
##
##  if ! [[ $SSD_SIZE_GB =~ $number_re ]] ; then
##    error "number of nodes must be a numeric value"
##    echo ""
##    usage
##    exit 1
##  fi
##
##  local zone_match=0
##  for zone in "${VALID_ZONES[@]}"; do
##    if [[ $zone = "$ZONE" ]]; then
##        zone_match=1
##        break
##    fi
##  done
##
##  if [[ $zone_match = 0 ]]; then
##    error "invalid gce zone.  Refer to the following url for list of valid zones:"
##    error "https://cloud.google.com/compute/docs/regions-zones/regions-zones"
##    echo ""
##    usage
##    exit 1
##  fi
##
##  # Get region from zone (everything to last dash)
##  REGION=$(echo $ZONE | sed "s/-[^-]*$//")
}


# Make sure we have all the right stuff
prerequisites() {
  if ! command_exists kops; then
    error "kops does not appear to be installed. Please install and re-run this script."
    exit 1
  fi
  
  if ! command_exists aws; then
    error "aws cli does not appear to be installed. Please install and re-run this script."
    exit 1
  fi

  if ! command_exists kubectl; then
    error "kubectl does not appear to be installed. Please install and re-run this script."
    exit 1
  fi
}

set_compute_zone()
{
##  gcloud config set compute/zone "$ZONE"
##  PROJECT_ID=$(gcloud config list project | sed -n 2p | cut -d " " -f 3)
echo "need to set compute zone"
}


cluster_up()
{
  export KOPS_STATE_STORE=s3://$S3_STATE_STORE
  
  inf ""
  inf "****************************************"
  inf "* Creating cluster:"
##  inf "*   Project ID: $PROJECT_ID"
  inf "*   Zone: $ZONE"
  inf "*   Cluster name: $CLUSTER_NAME"
  inf "*   Master type: $MASTER_TYPE"
  inf "*   Node type: $NODE_TYPE"
  inf "*   Num of nodes: $NUM_NODES"
  inf "*   S3 bucket for state storage: $KOPS_STATE_STORE"
  inf "****************************************"
  inf ""

  # options for how cluster is created
##  local cluster_options
##  cluster_options="--machine-type $MACHINE_TYPE --num-nodes $NUM_NODES --scopes storage-rw"
##
##  cluster_options="$cluster_options,service-control,logging-write,datastore,sql,sql-admin,bigquery"
##
##  if [ "$NUM_LOCAL_SSD" -gt 0 ]; then
##    cluster_options="$cluster_options --local-ssd-count=$NUM_LOCAL_SSD"
##  fi
##
##  gcloud container clusters create "$CLUSTER_NAME" $(echo "$cluster_options")
  kops create cluster --cloud=aws --zones=$ZONE \
    --node-size=$NODE_TYPE --master-size=$MASTER_TYPE \
    --node-count=$NUM_NODES --state=$KOPS_STATE_STORE \
    $CLUSTER_NAME

  kops update cluster --name=$CLUSTER_NAME --state=$KOPS_STATE_STORE --yes
}


create_kubectl_config()
{
  inf ""
  inf ""
  inf "Creating kubectl config..."

##  gcloud config set container/cluster "$CLUSTER_NAME"
##  gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE"
#  export KOPS_STATE_STORE=s3://$
# NAME=<kubernetes.mydomain.com>
  kops export kubecfg ${CLUSTER_NAME}
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
}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path "$0")"
  cmdline $ARGS
  valid_args
  prerequisites
##  set_compute_zone
  cluster_up
  create_kubectl_config

  # Creating SSDs and attach to container engine nodes
  if [ "$SSD_SIZE_GB" -gt 0 ]; then
    attach_disk
  fi

##  dump_cluster_status
}

##kops update cluster --name=dev.k8s.lowdrag.io --state=s3://k8s.mystique.dev.state --yes
##kops export kubecfg --name=dev.k8s.lowdrag.io --state=s3://k8s.mystique.dev.state
##Suggestions:
## * list clusters with: kops get cluster
## * edit this cluster with: kops edit cluster dev.k8s.lowdrag.io
## * edit your node instance group: kops edit ig --name=dev.k8s.lowdrag.io nodes
## * edit your master instance group: kops edit ig --name=dev.k8s.lowdrag.io master-us-east-1a


[[ "$0" == "$BASH_SOURCE" ]] && main
