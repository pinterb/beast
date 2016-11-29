#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

# http://www.kfirlavi.com/blog/2012/11/14/defensive-bash-programming/

readonly PROGNAME=$(basename $0)
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"
readonly ARGS="$@"
readonly TODAY=$(date +%Y%m%d%H%M%S)

# find project root directory using git
readonly PROJECT_ROOT=$(readlink -f $(git rev-parse --show-cdup))

# pull in utils
[[ -f "$PROJECT_ROOT/secrets/utils.sh" ]] && source "$PROJECT_ROOT/secrets/utils.sh"

# cli arguments
SECRET_NAME=
USE_DNSIMPLE=
TEMP_SECRET_DIR=

usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME creates a Kubernetes secret for Let's Encrypt certificates. Specifically, it populates a k8s secret with local
  environment variables that correspond to DNS providers that can be used for ACME challenge providers.

  OPTIONS:
    -n --name                kubernetes secret name
    --dnsimple               create secret for DNSimple
    -h --help                show this help


  Examples:
    $PROGNAME --name=dnsimple-acme --dnsimple
EOF
}


cmdline() {
  if [ "$#" -lt 1 ]; then
    usage
    exit
  fi

  for arg in "$@"; do
    case $arg in
      -h|-\?|--help)   # Call a "usage" function to display a synopsis, then exit.
        usage
        exit
        ;;
      -n|--name)       # Takes an option argument, ensuring it has been specified.
        if [ -n "$2" ]; then
          SECRET_NAME=$2
          shift
        else
          error "'--name' requires a non-empty option argument. "
          exit 1
        fi
        ;;
      --name=?*)
        SECRET_NAME=${1#*=} # Delete everything up to "=" and assign the remainder.
        ;;
      --name=)         # Handle the case of an empty --file=
        error "'--name' requires a non-empty option argument. "
        exit 1
        ;;
      --dnsimple)
        USE_DNSIMPLE=0
        ;;
      --)              # End of all options.
        shift
        break
        ;;
      -?*)
        error "Unknown option"
        usage
        exit 1
        ;;
      *)               # Default case: If no more options then break out of the loop.
        break
    esac

    shift
  done

  return 0
}


valid_args()
{
  inf ""
  inf "validating arguments..."
  inf ""
}


# Make sure we have all the right stuff
prerequisites() {
  inf ""
  inf "verifying prerequisites..."
  inf ""

  if ! command_exists kubectl; then
    error "kubectl does not appear to be installed. Please install and re-run this script."
    exit 1
  fi

  if ! cluster_exists; then
    error "A Kubernetes cluster does not seem to be provisioned.  Please verify the Kubernetes cluster and then re-run this script."
    exit 1
  fi
}


make_temp_dir()
{
  TEMP_SECRET_DIR="/tmp/$$"

  if [ ! -d "$TEMP_SECRET_DIR" ]; then
    echo ""
    inf "Creating temporary directory..."
    echo ""
    mkdir -p "$TEMP_SECRET_DIR"
  fi
}


clean_up()
{
  if [ -n "$TEMP_SECRET_DIR" ]; then
    rm -rf "$TEMP_SECRET_DIR"
  fi
}


use_dnsimple()
{
  inf ""
  inf "validating dnsimple env vars..."
  inf ""

  if [ -z "$DNSIMPLE_EMAIL" ]; then
    error "Missing DNSimple environment variable: 'DNSIMPLE_EMAIL'"
    exit 1
  fi

  if [ -z "$DNSIMPLE_API_KEY" ]; then
    error "Missing DNSimple environment variable: 'DNSIMPLE_API_KEY'"
    exit 1
  fi

  make_temp_dir
  #echo "$DNSIMPLE_EMAIL" > "$TEMP_SECRET_DIR/dnsimple_email.txt"
  #echo "$DNSIMPLE_API_KEY" > "$TEMP_SECRET_DIR/dnsimple_api_key.txt"
  echo -n "$DNSIMPLE_EMAIL" > "$TEMP_SECRET_DIR/dnsimple_email"
  echo -n "$DNSIMPLE_API_KEY" > "$TEMP_SECRET_DIR/dnsimple_api_key"

  for f in "$TEMP_SECRET_DIR"/*
  do
    echo "Logging $f file..."
    FILES+=("$f")
  done
}


create_kube_secret()
{
  echo ""
  inf "Create kubernetes secrects..."
  echo ""

  if [ -z "$FILES" ]; then
    clean_up
    error "No dns secrets were identified for creating this kubernetes secret. Did you select a dns provider?"
    usage
    exit 1
  fi

  local cmd_opts="secret generic $SECRET_NAME"
  for val in "${FILES[@]}"; do
    cmd_opts="$cmd_opts --from-file=$val"
  done

  kubectl create $cmd_opts
  kubectl describe secrets "$SECRET_NAME"
}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path $0)"
  cmdline $ARGS
  valid_args
  prerequisites

  if [ -n "$USE_DNSIMPLE" ]; then
    use_dnsimple
  fi

  create_kube_secret
  clean_up
}

[[ "$0" == "$BASH_SOURCE" ]] && main
