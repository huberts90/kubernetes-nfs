#!/bin/sh

set -e

# The Docker host kernel needs the `nfs` and `nfsd` modules to successfully boot NFS pod in k8s
# See more for reference https://hub.docker.com/r/erichough/nfs-server/
for module in "nfs" "nfsd"; do
  if lsmod | grep -Eq "^$module\\s+" || [ -d "/sys/module/$module" ]; then
    echo "$module module is not loaded in the Docker host's kernel. Loading..."
    modprobe $module
  fi
done

if ! [ -x "$(command -v k3d)" ]; then
  echo 'Error: k3d is not installed. Please visit https://k3d.io for further details.' >&2
  exit 1
fi

MAX_RETRIES=30
CLUSTER=k8s-nfs
NAMESPACE=k8s-nfs

# Delete old cluster before attempting to run the test
if (k3d cluster list | grep -q ${CLUSTER}); then
  echo "Deleting resources from previous run"
  kubectl delete pods --all --wait=false
  kubectl delete pvc --all --wait=false
  kubectl delete pv --all --wait=false
  echo "Deleting old cluster ${CLUSTER}"
  k3d cluster delete $CLUSTER
fi

# Create new kubernetes cluster
k3d cluster create ${CLUSTER}
sleep 5

# Create namespace
kubectl create -f "k8s/namespace.json"
kubectl config set-context --current --namespace ${NAMESPACE}

kubectl apply -f "k8s/nfs-server/nfs-server.yaml"

n=0
until [ "$n" -ge $MAX_RETRIES ]; do
  kubectl logs nfs-server && break
  n=$((n + 1))
  sleep 5
done

# Get dynamically assigned IP of nfs server
NFS_IP=$(kubectl get pod -o custom-columns=":status.podIP" nfs-server | tr -d " \t\n\r")
echo "NFS_IP: ${NFS_IP}"
TPL_NFS_CLIENT=$(cat "k8s/nfs-client/nfs-client.yaml" | sed "s/NFS_IP/${NFS_IP}/g")
echo "$TPL_NFS_CLIENT" | kubectl apply -f -

kubectl logs nfs-server
kubectl describe pod nfs-client

sleep 300
kubectl logs nfs-client