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

```
gcloud container clusters create mystique-dev --zone us-central1-c  
gcloud components install kubectl  
gcloud components update  
gcloud container clusters describe mystique-dev --zone us-central1-c 
gcloud container clusters list --zone us-central1-c 
gcloud container clusters get-credentials mystique-dev --zone us-central1-c 
gcloud container clusters delete mystique-dev --zone us-central1-c 

mkdir -p $HOME/bin
wget -O /tmp/gcloud.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-116.0.0-linux-x86_64.tar.gz  
tar -xzf /tmp/gcloud.tar.gz -C $HOME/bin
cd $HOME/bin  
$HOME/bin/google-cloud-sdk/install.sh --usage-reporting true --command-completion true --path-update true --rc-path $HOME/.bashrc --quiet 
rm /tmp/gcloud.tar.gz
  
