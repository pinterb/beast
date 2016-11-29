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

readonly VALID_DNS_PROVIDERS=(cloudflare digitalocean dnsimple dnsmadeeasy gandi linode manual namecheap rfc2136 route53 dyn vultr ovh pdns)

# cli arguments
SECRET_NAME=
DOMAIN_NAME=
DNS_PROVIDER_NAME=
EMAIL_ADDRESS=
LEGO_OUTPUT_DIR="$HOME/.lego"


usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME is a thin wrapper around the lego cli for Let's Encrpt. Lego created certs are then passed into
  Kubernetes as tls secrets.

  OPTIONS:
    -n --name                kubernetes secret name (default: the specified domain)
    -d --domain              domain name that certificate will be created for
    -c --dns                 DNS provider used for ACME DNS challenge
    -e --email               email address of user
    -p --path                the directory where lego will write certificate (default: $LEGO_OUTPUT_DIR)
    -h --help                show this help

  Valid DNS providers and their associated credential environment variables:

        cloudflare:     CLOUDFLARE_EMAIL, CLOUDFLARE_API_KEY
        digitalocean:   DO_AUTH_TOKEN
        dnsimple:       DNSIMPLE_EMAIL, DNSIMPLE_API_KEY
        dnsmadeeasy:    DNSMADEEASY_API_KEY, DNSMADEEASY_API_SECRET
        gandi:          GANDI_API_KEY
        gcloud:         GCE_PROJECT
        linode:         LINODE_API_KEY
        manual:         none
        namecheap:      NAMECHEAP_API_USER, NAMECHEAP_API_KEY
        rfc2136:        RFC2136_TSIG_KEY, RFC2136_TSIG_SECRET,
                        RFC2136_TSIG_ALGORITHM, RFC2136_NAMESERVER
        route53:        AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
        dyn:            DYN_CUSTOMER_NAME, DYN_USER_NAME, DYN_PASSWORD
        vultr:          VULTR_API_KEY
        ovh:            OVH_ENDPOINT, OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY
        pdns:           PDNS_API_KEY, PDNS_API_URL


  Examples:
    $PROGNAME --email bpinter@mailbag.com --domain cdw.lowdrag.io --dns route53

    $PROGNAME --email brad.pinter@gmail.com --name cdw.cloudutils.io --domain cdw.cloudutils.io --dns dnsimple
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
      --dns)            args="${args}-c ";;
      --domain)         args="${args}-d ";;
      --email)          args="${args}-e ";;
      --path)           args="${args}-p ";;
      --help)           args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
          args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- $args

  while getopts ":n:c:d:e:p:h" OPTION
  do
     case $OPTION in
     n)
         SECRET_NAME=$OPTARG
         ;;
     d)
         DOMAIN_NAME=$OPTARG
         ;;
     c)
         DNS_PROVIDER_NAME=$OPTARG
         ;;
     e)
         EMAIL_ADDRESS=$OPTARG
         ;;
     p)
         LEGO_OUTPUT_DIR=$OPTARG
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

  if [ -z "$DOMAIN_NAME" ]; then
    error "A domain name is required."
    echo ""
    usage
    exit 1
  fi

  if [ -z "$SECRET_NAME" ]; then
    SECRET_NAME="$DOMAIN_NAME"
    warn "A kubernetes secret name was not provided.  Will use \"$SECRET_NAME\" as the secret name."
    echo ""
  fi


  if [ -z "$DNS_PROVIDER_NAME" ]; then
    error "A dns provider name is required."
    echo ""
    usage
    exit 1
  fi

  local provider_match=0
  for provider in "${VALID_DNS_PROVIDERS[@]}"; do
    if [[ $provider = "$DNS_PROVIDER_NAME" ]]; then
        provider_match=1
        break
    fi
  done

  if [[ $provider_match = 0 ]]; then
    error "Invalid dns provider."
    echo ""
    usage
    exit 1
  fi

  if [ -z "$EMAIL_ADDRESS" ]; then
    error "An email address is required."
    echo ""
    usage
    exit 1
  fi
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

  if ! command_exists lego; then
    error "lego does not appear to be installed. Please install and re-run this script."
    exit 1
  fi

  if ! cluster_exists; then
    error "A Kubernetes cluster does not seem to be provisioned.  Please verify the Kubernetes cluster and then re-run this script."
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


create_lego_cert()
{
  echo ""
  inf "Creating Let's Encrypt cert..."
  echo ""

  mkdir -p "$LEGO_OUTPUT_DIR"

  lego --dns "$DNS_PROVIDER_NAME" --domains "$DOMAIN_NAME" --email "$EMAIL_ADDRESS" --path "$LEGO_OUTPUT_DIR" run

  local expected_cert_file="$LEGO_OUTPUT_DIR/certificates/$DOMAIN_NAME.crt"
  if [ ! -f "$expected_cert_file" ]; then
    echo ""
    error "Missing expected file: $expected_cert_file"
    echo ""
    exit 1
  fi

  local expected_key_file="$LEGO_OUTPUT_DIR/certificates/$DOMAIN_NAME.key"
  if [ ! -f "$expected_key_file" ]; then
    echo ""
    error "Missing expected file: $expected_key_file"
    echo ""
    exit 1
  fi

  local expected_json_file="$LEGO_OUTPUT_DIR/certificates/$DOMAIN_NAME.json"
  if [ ! -f "$expected_json_file" ]; then
    echo ""
    error "Missing expected file: $expected_json_file"
    echo ""
    exit 1
  fi
}


create_kube_secret()
{
  echo ""
  inf "Create kubernetes secrect..."
  echo ""

  local expected_cert_file="$LEGO_OUTPUT_DIR/certificates/$DOMAIN_NAME.crt"
  local expected_key_file="$LEGO_OUTPUT_DIR/certificates/$DOMAIN_NAME.key"

  kubectl create secret tls $SECRET_NAME --cert=$expected_cert_file --key=$expected_key_file
  kubectl label secrets $SECRET_NAME domain=$DOMAIN_NAME
  echo ""
  echo ""
  kubectl describe secrets "$SECRET_NAME"
}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path $0)"
  cmdline $ARGS
  valid_args
  prerequisites
  create_lego_cert
  create_kube_secret
}

[[ "$0" == "$BASH_SOURCE" ]] && main
