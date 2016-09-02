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

DEFAULT_NODE_TYPE=${AWS_K8S_NODE_TYPE:-'t2.medium'}
DEFAULT_MASTER_TYPE=${AWS_K8S_MASTER_TYPE:-'m3.large'}
DEFAULT_CLUSTER_NAME=${AWS_K8S_CLUSTER_NAME:-'dev.k8s'}
DEFAULT_DOMAIN_NAME=${AWS_DEFAULT_ROUTE53_DOMAIN:-'lowdrag.io'}
DEFAULT_NUM_NODES=${AWS_DEFAULT_K8S_NUM_NODES:-2}

DEFAULT_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
DEFAULT_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
DEFAULT_STATE_STORE=${AWS_DEFAULT_S3_BUCKET:-'k8s.mystique.dev.state'}
DEFAULT_REGION=${AWS_DEFAULT_REGION:-'us-east-1'}
DEFAULT_ZONE=${AWS_ZONE:-'c'}

# cli arguments
ZONES=
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
  (see https://github.com/kubernetes/kops)

  OPTIONS:
    -c --cluster-name        name of container engine cluster (default: ${DEFAULT_CLUSTER_NAME}.${DEFAULT_DOMAIN_NAME})
    -n --num-nodes           number of cluster nodes (default: $DEFAULT_NUM_NODES)
    -s --state-store         aws s3 bucket used for cluster state storage (default: $DEFAULT_STATE_STORE)
    -t --node-type           aws ec2 instance type for k8s node (default: $DEFAULT_NODE_TYPE)
    -x --master-type         aws ec2 instance type for k8s master (default: $DEFAULT_MASTER_TYPE)
    -z --zones               comma separated list of aws zones (default: ${DEFAULT_REGION}${DEFAULT_ZONE})
    -h --help                show this help


  Examples:
    $PROGNAME --cluster-name dev.k8s.lowdrag.io --state-store k8s.mystique.dev.state --zones us-east-1a,us-east-1c --num-nodes 10
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
      --zones)          args="${args}-z ";;
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
         ZONES=$OPTARG
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


valid_args() {
  ZONES=${ZONES:-"${DEFAULT_REGION}${DEFAULT_ZONE}"}
  NODE_TYPE=${NODE_TYPE:-"$DEFAULT_NODE_TYPE"}
  MASTER_TYPE=${MASTER_TYPE:-"$DEFAULT_MASTER_TYPE"}
  CLUSTER_NAME=${CLUSTER_NAME:-"${DEFAULT_CLUSTER_NAME}.${DEFAULT_DOMAIN_NAME}"}
  NUM_NODES=${NUM_NODES:-"$DEFAULT_NUM_NODES"}

  S3_STATE_STORE=${S3_STATE_STORE:-"$DEFAULT_STATE_STORE"}
  FMT_STATE_STORE="s3://$S3_STATE_STORE"

  if ! s3_bucket_exists "$S3_STATE_STORE"; then
    error "the aws s3 bucket '$S3_STATE_STORE' doesn't appear to exist."
    exit 1
  fi

  local number_re='^[0-9]+$'
  if ! [[ $NUM_NODES =~ $number_re ]] ; then
    error "number of nodes must be a numeric value"
    echo ""
    usage
    exit 1
  fi

  echo "$ZONES" | sed -n 1'p' | tr ',' '\n' | while read zone; do
    if ! valid_zone "$zone"; then
      error "'$zone' is not a valid aws availability zone."
      exit 1
    fi
  done
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


cluster_up() {
  inf ""
  inf "****************************************"
  inf "* Creating cluster:"
  inf "*   Zones: $ZONES"
  inf "*   Cluster name: $CLUSTER_NAME"
  inf "*   Master type: $MASTER_TYPE"
  inf "*   Node type: $NODE_TYPE"
  inf "*   Num of nodes: $NUM_NODES"
  inf "*   S3 bucket for state storage: $FMT_STATE_STORE"
  inf "****************************************"
  inf ""

  if ! cluster_exists "$FMT_STATE_STORE" "$CLUSTER_NAME"; then
    kops create cluster --cloud=aws --zones=$ZONES \
      --node-size=$NODE_TYPE --master-size=$MASTER_TYPE \
      --node-count=$NUM_NODES --state=$FMT_STATE_STORE \
      $CLUSTER_NAME
  fi

  kops update cluster --name=$CLUSTER_NAME --state=$FMT_STATE_STORE --yes
}


create_kubectl_config() {
  inf ""
  inf ""
  inf "Creating kubectl config..."

  kops export kubecfg --state=$FMT_STATE_STORE $CLUSTER_NAME 
}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path "$0")"
  cmdline $ARGS
  prerequisites
  valid_args
  cluster_up
  create_kubectl_config
}

[[ "$0" == "$BASH_SOURCE" ]] && main
