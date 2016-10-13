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
GEN_CERT=
TEMP_CERT_DIR=


usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME takes files and creates a Kubernetes secret with them. It is intended to be used for storing
  TLS certificates in Kubernetes.  But it could be used to store any arbitrary file in Kubernetes as a secret.

  OPTIONS:
    -n --name                kubernetes secret name

    -f --file                file to be added to secret (NOTE: you can enter multiple files)

    -g --gen-dummy-cert      automatically generate a dummy, self-signed openssl cert
                             (NOTE: you would typically use instead of -f option)

    -h --help                show this help


  Examples:
    $PROGNAME --name web-app-secret --file /tmp/tls.crt --file /tmp/tls.key
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
      --name)           args="${args}-n ";;
      --file)           args="${args}-f ";;
      --gen-cert)       args="${args}-g ";;
      --help)           args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
          args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- $args

  while getopts ":n:f:gh" OPTION
  do
     case $OPTION in
     n)
         SECRET_NAME=$OPTARG
         ;;
     f)
         FILES+=("$OPTARG")
         ;;
     g)
         readonly GEN_CERT=1
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

  if ! command_exists openssl; then
    error "openssl does not appear to be installed. Please install and re-run this script."
    exit 1
  fi
}


make_temp_dir()
{
  echo ""
  inf "Creating self-signed, dummy cert..."
  echo ""

  TEMP_CERT_DIR="/tmp/$$"
  openssl req \
    -newkey rsa:2048 -nodes -keyout "$TEMP_CERT_DIR/tls.key" \
    -x509 -days 365 -out "$TEMP_CERT_DIR/tls.crt"
}


auto_create_cert()
{
  echo ""
  inf "Creating self-signed, dummy cert..."
  echo ""

  local COUNTRY=US
  local STATE=Wisconsin
  local CITY=Madison
  local COMPANY=CDW
  local COMMON=hackcity

  TEMP_CERT_DIR="/tmp/$$"
  mkdir -p "$TEMP_CERT_DIR"

  openssl req \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${COMPANY}/CN=${COMMON}" \
    -newkey rsa:2048 -nodes -keyout "$TEMP_CERT_DIR/tls.key" \
    -x509 -days 365 -out "$TEMP_CERT_DIR/tls.crt"

  for f in "$TEMP_CERT_DIR"/*
  do
    echo "Logging $f file..."
    FILES+=("$f")
  done
}


create_kube_secret()
{
  echo ""
  inf "Create kubernetes secrect..."
  echo ""

  if [ -z "$FILES" ]; then
    error "No files were identified for use with this secret.  Either auto-create or specify directly!"
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

  if [ -n "$GEN_CERT" ]; then
    auto_create_cert
  fi

  create_kube_secret

  if [ -n "$TEMP_CERT_DIR" ]; then
    rm -rf "$TEMP_CERT_DIR"
  fi
}

[[ "$0" == "$BASH_SOURCE" ]] && main
