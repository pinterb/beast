#!/bin/bash -

readonly VALID_ZONES=(us-west1-a us-west1-b us-central1-a us-central1-b us-central1-c us-central1-f us-east1-b us-east1-c us-east1-d europe-west1-b europe-west1-c europe-west1-d asia-east1-a asia-east1-b asia-east1-c)

cluster_exists() {
  gcloud container clusters describe "$@" > /dev/null 2>&1
}

# check component status are all healthy
component_status() {
  inf ""
  inf "Cluster components status:"
  inf ""
  kubectl get cs
}

# check if master is running
cluster_info() {
  inf ""
  inf "Cluster info:"
  inf ""
  kubectl cluster-info
}

# get cluster nodes
get_nodes() {
  inf ""
  inf "Cluster nodes:"
  inf ""
  kubectl get nodes
}

# thin wrapper for kubectl create -f filename
create() {
  inf ""
  inf "Executing 'kubectl create -f $@'..."
  inf ""
  kubectl create -f "$@"
}

# thin wrapper for kubectl scale deployment 
scale_deployment() {
  inf ""
  inf "Executing 'kubectl scale deployment $@'..."
  inf ""
  kubectl scale deployment "$@"
}

# thin wrapper for kubectl delete pod $@
delete_pod() {
  inf ""
  inf "Executing 'kubectl delete pod $@'..."
  inf ""
  kubectl delete pod "$@"
}

# thin wrapper for kubectl delete deployment $@
delete_deployment() {
  inf ""
  inf "Executing 'kubectl delete deployment $@'..."
  inf ""
  kubectl delete deployment "$@"
}

# thin wrapper for kubectl delete service $@
delete_service() {
  inf ""
  inf "Executing 'kubectl delete service $@'..."
  inf ""
  kubectl delete service "$@"
}


# get cluster pods
get_pods() {
  inf ""
  if [[ $# -eq 0 ]] ; then
    inf "Cluster pods:"
    inf ""
    kubectl get pods -o wide
  else
    inf "Cluster pods (--selector=$@):"
    inf ""
    kubectl get pods -o wide
    #kubectl get pods -o wide -l "$@"
  fi
}


# get cluster deployments
get_deployments() {
  inf ""
  inf "Cluster deployments:"
  inf ""
  kubectl get deployments 
}


# get cluster services
get_services() {
  inf ""
  inf "Cluster services:"
  inf ""
  kubectl get services 
}
