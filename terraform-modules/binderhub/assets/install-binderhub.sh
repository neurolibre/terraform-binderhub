#!/bin/bash
#waiting for k8s initialization
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 10; done
while [ ! -f /shared/k8s-initialized ]; do sleep 1; done

cd /home/${admin_user}

# node helath monitoring
sudo helm repo add deliveryhero https://charts.deliveryhero.io/
sudo helm install deliveryhero/node-problem-detector --generate-name --kubeconfig ~/.kube/config

#Persistent volume
kubectl create -f pv.yaml

# TLS certificate management
# cert-manager
kubectl create namespace cert-manager
sudo helm repo add jetstack https://charts.jetstack.io
sudo helm repo update
# running on master node to avoid issues with webhook not in the k8s network
sudo helm install cert-manager --namespace cert-manager --version v1.9.0 jetstack/cert-manager --set installCRDs=true \
  --set nodeSelector."node-role\.kubernetes\.io/master=" \
  --set cainjector.nodeSelector."node-role\.kubernetes\.io/master=" \
  --set webhook.nodeSelector."node-role\.kubernetes\.io/master=" \
  --kubeconfig ~/.kube/config
#wait until cert-manager is ready
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=300s
# apply the issuer(s)
kubectl create namespace binderhub
# kubectl apply -f staging-binderhub-issuer.yaml
kubectl apply -f production-binderhub-issuer.yaml

# Binderhub proxy
sudo helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx/
sudo helm install binderhub-proxy ingress-nginx/ingress-nginx --namespace=binderhub -f nginx-ingress.yaml --kubeconfig ~/.kube/config --version 4.1.4
# wait until nginx is ready (https://kubernetes.github.io/ingress-nginx/deploy/)
kubectl wait --namespace binderhub \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
kubectl get services --namespace binderhub binderhub-proxy-ingress-nginx-controller

# Binderhub
# schedule binderhub core pods just on master
# https://alan-turing-institute.github.io/hub23-deploy/advanced/optimising-jupyterhub.html#labelling-nodes-for-core-purpose
kubectl label nodes neurolibre-master hub.jupyter.org/node-purpose=core
sudo helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
sudo helm repo update
sudo helm install binderhub jupyterhub/binderhub --version=${binder_version} \
  --namespace=binderhub -f config.yaml -f secrets.yaml \
  --set-file jupyterhub.singleuser.extraFiles.repo2data.stringData=./repo2data.bash \
  --set-file jupyterhub.singleuser.extraFiles.fill_submission_metadata.stringData=./fill_submission_metadata.bash \
  --set-file jupyterhub.singleuser.extraFiles.jb_build.stringData=./jb_build.bash \
  --kubeconfig ~/.kube/config
# sudo helm upgrade binderhub jupyterhub/binderhub -n binderhub --version=${binder_version} \
#   -f confgi.yaml -f secrets.yaml \
#   --set-file jupyterhub.singleuser.extraFiles.repo2data.stringData=./repo2data.bash \
#   --set-file jupyterhub.singleuser.extraFiles.fill_submission_metadata.stringData=./fill_submission_metadata.bash \
#   --set-file jupyterhub.singleuser.extraFiles.jb_build.stringData=./jb_build.bash \
#   --kubeconfig ~/.kube/config
kubectl wait --namespace binderhub \
  --for=condition=ready pod \
  --selector=release=binderhub \
  --timeout=120s

# Grafana and prometheus
# https://github.com/pangeo-data/pangeo-binder#binder-monitoring
# sudo helm repo add grafana https://grafana.github.io/helm-charts
# sudo helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# sudo helm repo add kube-state-metrics https://kubernetes.github.io/kube-state-metrics
# sudo helm repo update
# sudo helm install grafana-prod grafana/grafana --kubeconfig ~/.kube/config
# sudo helm install prometheus-prod prometheus-community/prometheus --kubeconfig ~/.kube/config