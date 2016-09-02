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
CLUSTER_NAME=
S3_STATE_STORE=


usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME destroys a Kubernetes cluster on AWS using the kops cli utility.
  (see https://github.com/kubernetes/kops) 

  OPTIONS:
    -c --cluster-name        name of container engine cluster (default: ${DEFAULT_CLUSTER_NAME}.${DEFAULT_DOMAIN_NAME})
    -s --state-store         aws s3 bucket used for cluster state storage (default: $DEFAULT_STATE_STORE)
    -h --help                show this help


  Examples:
    $PROGNAME --cluster-name dev.k8s.lowdrag.io --state-store k8s.mystique.dev.state
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
      --state-store)    args="${args}-s ";;
      --help)           args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
          args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- "$args"

  while getopts ":c:s:h" OPTION
  do
     case $OPTION in
     c)
         CLUSTER_NAME=$OPTARG
         ;;
     s)
         S3_STATE_STORE=$OPTARG
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
  CLUSTER_NAME=${CLUSTER_NAME:-"${DEFAULT_CLUSTER_NAME}.${DEFAULT_DOMAIN_NAME}"}
  S3_STATE_STORE=${S3_STATE_STORE:-"$DEFAULT_STATE_STORE"}
  FMT_STATE_STORE="s3://$S3_STATE_STORE"

  if ! s3_bucket_exists "$S3_STATE_STORE"; then
    error "the aws s3 bucket '$S3_STATE_STORE' doesn't appear to exist."
    exit 1
  fi

  if ! cluster_exists "$FMT_STATE_STORE" "$CLUSTER_NAME"; then
    error "the kops k8s cluster '$CLUSTER_NAME' doesn't appear to exist."
    exit 1
  fi
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


cluster_down()
{
  inf ""
  inf "****************************************"
  inf "* Deleting cluster:"
  inf "*   Cluster name: $CLUSTER_NAME"
  inf "*   S3 bucket for state storage: $FMT_STATE_STORE"
  inf "****************************************"
  inf ""
  
  kops delete cluster --state=$FMT_STATE_STORE \
    --name=$CLUSTER_NAME \
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
  prerequisites
  valid_args
  cluster_down
}

[[ "$0" == "$BASH_SOURCE" ]] && main
