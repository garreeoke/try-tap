#!/bin/bash
#set -e

# TODO Setup args etc after it is working

######## Script starts here
KUBERNETES_CONTEXT=default
NAMESPACE=tap-install
OUT="./try-tap.log"
KAPP_VERSION="v0.39.0"
YTT_VERSION="v0.36.0"
IMGPKG_VERSION="v0.17.0"
KBLD_VERSION="v0.30.0"
KUBECTL_VERSION=v1.22.0
TANZU_CLI_VERSION="v1.4.0-rc.5" # Make an option
TBS_VERSION="1.2.2"

#TODO Checks for variables

### Load Helper Functions
. ./scripts/functions.sh

info "Running tap setup for Linux"

### Installing tools
install_kapp $KAPP_VERSION
install_ytt $YTT_VERSION
install_imgpkg $IMGPKG_VERSION
install_kbld $KBLD_VERSION
install_jq
install_yq
install_unzip
install_kubectl $KUBECTL_VERSION
install_tanzu_cli "$TANZU_NET_REFRESH_TOKEN" "$TANZU_CLI_VERSION"
install_helm
install kp "$TANZU_NET_REFRESH_TOKEN" "$TANZU_CLI_VERSION"

cfg_tanzu_net "$TANZU_NET_USER" "$TANZU_NET_PASSWORD"

### Set up Kubernetes environment
install_k3s
env "PATH=$PATH" kubectl config set-context ${KUBERNETES_CONTEXT}
echo '' >>~/.bashrc
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# Install kapp controller
echo "Installing kapp controller"
kapp deploy --yes -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml
# Setup package repo
kubectl create namespace tap-install
kubectl create secret docker-registry tap-registry -n tap-install --docker-server='registry.pivotal.io' --docker-username=$TANZU_NET_USER --docker-password=$TANZU_NET_PASSWORD
kapp deploy --yes -a tap-package-repo -n tap-install -f ./manifests/tap-package-repo.yaml
tanzu package repository list -n tap-install

rm -rf cli

## Install Cloud Native Runtimes
info "Installing CNR"
sed -i "s/TANZU-NET-USER/$TANZU_NET_USER/g" values/cnr-values.yaml
sleep 1
sed -i "s/TANZU-NET-PASSWORD/$TANZU_NET_PASSWORD/g" values/cnr-values.yaml
sleep 1
tanzu package install cloud-native-runtimes -p cnrs.tanzu.vmware.com -v 1.0.1 -n tap-install -f values/cnr-values.yaml --wait=false
info "waiting 60 seconds"
sleep 60
kubectl get svc envoy -n contour-external -o yaml | yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.annotations, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields, .spec.clusterIP, .spec.clusterIPs, .spec.ports[0].nodePort)' - > manifests/svc_envoy.yaml
sleep 1
sed -i "s/port: 80/port: 8080/g" manifests/svc_envoy.yaml
sleep 1
sed -i "s/ name: envoy/ name: envoy-8080/g" manifests/svc_envoy.yaml
sleep 1
kubectl apply -f manifests/svc_envoy.yaml

## Install flux and app accelerator
info "Installing flux"
kapp deploy --yes -a flux -f https://github.com/fluxcd/flux2/releases/download/v0.15.0/install.yaml
sleep 1
kubectl delete -n flux-system networkpolicies --all
info "Installing app accelerator ..."
sed -i "s/TANZU-NET-USER/$TANZU_NET_USER/g" values/app-acclerator-values.yaml
sleep 1
sed -i "s/TANZU-NET-PASSWORD/$TANZU_NET_PASSWORD/g" values/app-accelerator-values.yaml
sleep 1
tanzu package install app-accelerator -p accelerator.apps.tanzu.vmware.com -v 0.2.0 -n tap-install -f values/app-accelerator-values.yaml
sleep 60
kubectl get svc -n accelerator-system acc-ui-server -o yaml | yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.annotations, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields, .spec.clusterIP, .spec.clusterIPs, .spec.ports[0].nodePort, .spec.ports[1])' - > manifests/svc_accelerator.yaml
sleep 1
sed -i "s/port: 80/port: 8081/g" manifests/svc_accelerator.yaml
sleep 1
sed -i "s/ name: acc-ui-server/ name: acc-ui-server-8081/g" manifests/svc_accelerator.yaml
sleep 1
sed -i "s/type: ClusterIP/type: LoadBalancer/g" manifests/svc_accelerator.yaml
kubectl apply -f manifests/svc_accelerator.yaml
sleep 1
info "Installing sample accelerators ..."
kubectl apply -f manifests/sample-accelerators-0.2.yaml

## Install app live view
info "Installing app live view ..."
sed -i "s/TANZU-NET-USER/$TANZU_NET_USER/g" values/app-live-view-values.yaml
sleep 1
sed -i "s/TANZU-NET-PASSWORD/$TANZU_NET_PASSWORD/g" values/app-live-view-values.yaml
sleep 1
tanzu package install app-live-view -p appliveview.tanzu.vmware.com -v 0.1.0 -n tap-install -f values/app-live-view-values.yaml
sleep 1
tanzu package installed list -n tap-install

## Install harbor
info "Installing harbor ..."
helm repo add harbor https://helm.goharbor.io
kubectl create ns harbor
helm install tap-harbor harbor/harbor -n harbor --values values/harbor-values.yaml
# Wait for harbor service to have external ip and then change registries
# May delete if not needed
HARBOR_SVC=""
while [ "$HARBOR_SVC" == "" ]
do
        echo "Waiting for harbor service"
        sleep 1
        HARBOR_SVC=$(kubectl get svc harbor -n harbor | grep harbor | kubectl get svc harbor -n harbor | grep harbor | awk '{print $4}')
        echo "HARBOR_SVC: $HARBOR_SVC"
done
sed -i "s/harbor.external.ip/$HARBOR_SVC/g" manifests/registries.yaml
# Restart k3s
info "Add insecure registry and restart"
cp manifests/registries.yaml /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s
sleep 5

# Install TBS
info "Installing Tanzu Build Service ..."
# Login to local reg
docker login ${HARBOR_SVC}:8085
# Login to pivotal reg
docker login registry.pivotal.io -u $TANZU_NET_USER -p $TANZU_NET_PASSWORD
# Copy image from piv to local
imgpkg copy -b "registry.pivotal.io/build-service/bundle:${TBS_VERSION}" --to-repo ${HARBOR_SVC}:8085/library/build-service
# Deploy
ytt -f /tmp/bundle/values.yaml -f /tmp/bundle/config/ -v docker_repository='${HARBOR_SVC}:8085/library/build-service' -v docker_username='admin' -v docker_password='Harbor12345' -v tanzunet_username="$TANZU_NET_USER" -v tanzunet_password="$TANZU_NET_PASSWORD" | sudo bld -f /tmp/bundle/.imgpkg/images.yml | sudo kapp deploy -a tanzu-build-service -f- -y
sudo kapp deploy -a tanzu-build-service -f- -y --debug
# Kp command to see builders
kp clusterbuilder list