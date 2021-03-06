#!/bin/bash -

readonly VALID_ZONES=(us-west1-a us-west1-b us-central1-a us-central1-b us-central1-c us-central1-f us-east1-b us-east1-c us-east1-d europe-west1-b europe-west1-c europe-west1-d asia-east1-a asia-east1-b asia-east1-c)

cluster_exists() {
  gcloud container clusters describe "$@" > /dev/null 2>&1
}

