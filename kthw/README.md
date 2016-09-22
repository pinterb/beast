## Kubernetes the Hard Way  
Kubernetes is a challenge to set up correctly.  
The Kubernetes community is actively working to make installation better, and easier. 
   
Until there are better ways for installing Kubernetes *and* to keep the project moving forward, 
one or more shell scripts have been written to create a **development-only** Kubernetes cluster 
   
### Prerequisites   
- [x] The (gcloud)[https://cloud.google.com/sdk/] command line utility  
- [x] Your cloud provider credentials  
   
### Provisioning a Google Container Engine (GKE)   
These instructions are based on the GKE [documentation](https://cloud.google.com/container-engine/docs/clusters/operations).  
```
cd gke
gke/cluster-up.sh --cluster-name mystique-dev --num-nodes 5

gcloud container clusters describe mystique-dev | grep password
```
