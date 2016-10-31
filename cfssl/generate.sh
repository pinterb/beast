#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

readonly PROGNAME=$(basename $0)
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"

CERTS_CONFIG_DIR="${CERTS_CONFIG_DIR:-${PROGDIR}/config}"
CERTS_OUTPUT_DIR="${CERTS_OUTPUT_DIR:-${PWD}}"

CA_CONFIG_FILE="${CA_CONFIG_FILE:-${CERTS_CONFIG_DIR}/ca-config.json}"
CA_ROOT_CSR_CONFIG_FILE="${CA_ROOT_CSR_CONFIG_FILE:-${CERTS_CONFIG_DIR}/ca-root-csr.json}"
CA_INTER_CSR_CONFIG_FILE="${CA_INTER_CSR_CONFIG_FILE:-${CERTS_CONFIG_DIR}/ca-intermediate-csr.json}"

CA_ROOT_CERT_FILE="${CA_ROOT_CERT_FILE:-${CERTS_OUTPUT_DIR}/root_ca.pem}"
CA_ROOT_KEY_FILE="${CA_ROOT_KEY_FILE:-${CERTS_OUTPUT_DIR}/root_ca-key.pem}"
CA_ROOT_CSR_FILE="${CA_ROOT_CSR_FILE:-${CERTS_OUTPUT_DIR}/root_ca.csr}"

CA_INTER_CERT_FILE="${CA_INTER_CERT_FILE:-${CERTS_OUTPUT_DIR}/intermediate_ca.pem}"
CA_INTER_KEY_FILE="${CA_INTER_KEY_FILE:-${CERTS_OUTPUT_DIR}/intermediate_ca-key.pem}"
CA_INTER_CSR_FILE="${CA_INTER_CSR_FILE:-${CERTS_OUTPUT_DIR}/intermediate_ca.csr}"

SERVER_CSR_CONFIG_FILE="${SERVER_CSR_CONFIG_FILE:-${CERTS_CONFIG_DIR}/server-csr.json}"
SERVER_CERT_FILE="${SERVER_CERT_FILE:-${CERTS_OUTPUT_DIR}/cert.pem}"
SERVER_KEY_FILE="${SERVER_KEY_FILE:-${CERTS_OUTPUT_DIR}/cert-key.pem}"
SERVER_CSR_FILE="${SERVER_CSR_FILE:-${CERTS_OUTPUT_DIR}/cert.csr}"

CLIENT_CSR_CONFIG_FILE="${CLIENT_CSR_CONFIG_FILE:-${CERTS_CONFIG_DIR}/client-csr.json}"
CLIENT_CERT_FILE="${CLIENT_CERT_FILE:-${CERTS_OUTPUT_DIR}/client.pem}"
CLIENT_KEY_FILE="${CLIENT_KEY_FILE:-${CERTS_OUTPUT_DIR}/client-key.pem}"
CLIENT_CSR_FILE="${CLIENT_CSR_FILE:-${CERTS_OUTPUT_DIR}/client.csr}"

# pull in utils
source "${PROGDIR}/utils.sh"


prerequisites() {
  if ! command_exists cfssl; then
    error "cfssl does not appear to be installed.  please install and retry."
    exit 1
  fi

  if ! command_exists openssl; then
    error "openssl does not appear to be installed.  please install and retry."
    exit 1
  fi

  if [ ! -d "$CERTS_CONFIG_DIR" ]; then
    echo ""
    error "The cfssl configuration directory \"$CERTS_CONFIG_DIR\""
    error "does not exist.  Are you sure you have the right directory?"
  fi

  if [ ! -d "$CERTS_OUTPUT_DIR" ]; then
    echo ""
    inf "Creating $CERTS_OUTPUT_DIR"
    mkdir -p "$CERTS_OUTPUT_DIR"
  elif [ "$CERTS_OUTPUT_DIR" == "$PWD" ]; then
    echo ""
    warn "Certificates will be created in \"$PWD\"."
    sleep 8s
  fi

  if [ ! -f "$CA_CONFIG_FILE" ]; then
    echo ""
    inf "Initializing $CA_CONFIG_FILE"
    cfssl print-defaults config > "$CA_CONFIG_FILE"
  fi

  if [ ! -f "$CA_ROOT_CSR_CONFIG_FILE" ]; then
    echo ""
    inf "Initializing $CA_ROOT_CSR_CONFIG_FILE"
    cfssl print-defaults csr > "$CA_ROOT_CSR_CONFIG_FILE"
  fi

  if [ ! -f "$CA_INTER_CSR_CONFIG_FILE" ]; then
    echo ""
    inf "Initializing $CA_INTER_CSR_CONFIG_FILE"
    echo ""
    warn "WARNING: This newly created intermediate csr configuration file"
    warn "will probably not work as intended without modifications by you!!"
    cfssl print-defaults csr > "$CA_INTER_CSR_CONFIG_FILE"
  fi
}


gen_root_ca() {
  if [[ ! -f "$CA_ROOT_KEY_FILE" || ! -f "$CA_ROOT_CERT_FILE" ]]; then
    echo ""
    inf "Creating the Root CA"
    cd "$CERTS_OUTPUT_DIR" && \
      cfssl gencert \
      -initca "$CA_ROOT_CSR_CONFIG_FILE" | cfssljson -bare root_ca
  else
    echo ""
    warn "The root ca already exists.  Is that okay??"
  fi
}


verify_root_ca() {
  echo ""
  inf "Verifying the Root CA"
  cd "$CERTS_OUTPUT_DIR" && \
    openssl x509 -in "$CA_ROOT_CERT_FILE" -text -noout || exit 1
}


gen_intermediate_ca() {
  if [[ ! -f "$CA_INTER_KEY_FILE" || ! -f "$CA_INTER_CERT_FILE" ]]; then
    echo ""
    inf "Creating the Intermediate CA"
    cd "$CERTS_OUTPUT_DIR" && \
      cfssl gencert \
      -initca "$CA_INTER_CSR_CONFIG_FILE" \
      | cfssljson -bare intermediate_ca

    echo ""
    inf "Signing the Intermediate CA"
    cd "$CERTS_OUTPUT_DIR" && \
    cfssl sign \
      -ca root_ca.pem \
      -ca-key root_ca-key.pem \
      -config "$CA_CONFIG_FILE" \
      -profile root-to-intermediate-ca \
      intermediate_ca.csr | cfssljson -bare intermediate_ca
  else
    echo ""
    warn "The intermediate ca already exists.  Is that okay??"
  fi
}


verify_intermediate_ca() {
  echo ""
  inf "Verifying the Intermediate CA"
  cd "$CERTS_OUTPUT_DIR" && \
    openssl x509 -in "$CA_INTER_CERT_FILE" -text -noout || exit 1
}


gen_server_cert() {
  if [[ ! -f "$SERVER_KEY_FILE" || ! -f "$SERVER_CERT_FILE" ]]; then
    echo ""
    inf "Creating the server certificate"
    cd "$CERTS_OUTPUT_DIR" && \
    cfssl gencert \
      -ca intermediate_ca.pem \
      -ca-key intermediate_ca-key.pem \
      -config "$CA_CONFIG_FILE" \
      -profile server \
      "$SERVER_CSR_CONFIG_FILE" | cfssljson -bare
  else
    echo ""
    warn "The server certificate already exists.  Is that okay??"
  fi
}


verify_server_cert() {
  echo ""
  inf "Verifying the server certificate"
  cd "$CERTS_OUTPUT_DIR" && \
    openssl x509 -in "$SERVER_CERT_FILE" -text -noout
}


gen_client_cert() {
  if [[ ! -f "$CLIENT_KEY_FILE" || ! -f "$CLIENT_CERT_FILE" ]]; then
    echo ""
    inf "Creating the client certificate"
    cd "$CERTS_OUTPUT_DIR" && \
    cfssl gencert \
      -ca intermediate_ca.pem \
      -ca-key intermediate_ca-key.pem \
      -config "$CA_CONFIG_FILE" \
      -profile client \
      "$CLIENT_CSR_CONFIG_FILE" | cfssljson -bare client
  else
    echo ""
    warn "The client certificate already exists.  Is that okay??"
  fi
}


verify_client_cert() {
  echo ""
  inf "Verifying the client certificate"
  cd "$CERTS_OUTPUT_DIR" && \
    openssl x509 -in "$CLIENT_CERT_FILE" -text -noout
}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path $0)"
  prerequisites

  # Create root ca if doesn't already exist
  if [[ ! -f "$CA_ROOT_KEY_FILE" || ! -f "$CA_ROOT_CERT_FILE" ]]; then
    gen_root_ca
  fi
  verify_root_ca

  # Create intermediate ca if doesn't already exist
  if [[ ! -f "$CA_INTER_KEY_FILE" || ! -f "$CA_INTER_CERT_FILE" ]]; then
    gen_intermediate_ca
  fi
  verify_intermediate_ca

  # Create server certificate if doesn't already exist
  if [[ ! -f "$SERVER_KEY_FILE" || ! -f "$SERVER_CERT_FILE" ]]; then
    gen_server_cert
  fi
  verify_server_cert

  # Create client certificate if doesn't already exist
  if [[ ! -f "$CLIENT_KEY_FILE" || ! -f "$CLIENT_CERT_FILE" ]]; then
    gen_client_cert
  fi
  verify_client_cert
}


[[ "$0" == "$BASH_SOURCE" ]] && main
