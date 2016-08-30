#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

readonly PROGNAME=$(basename $0)
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"
readonly TODAY=$(date +%Y%m%d%H%M%S)

# find project root directory using git
readonly PROJECT_ROOT=$(readlink -f $(git rev-parse --show-cdup))

# pull in utils
[[ -f "$PROJECT_ROOT/kthw/utils.sh" ]] && source "$PROJECT_ROOT/kthw/utils.sh"

# pull in gcloud utils
[[ -f "$PROJECT_ROOT/kthw/gke/gcloud-utils.sh" ]] && source "$PROJECT_ROOT/kthw/gke/gcloud-utils.sh"

create consul-petset.yml

get_pods
