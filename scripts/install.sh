#!/bin/bash
#set -e

### SET ENVIRONMENT VARIABLES
# TANZU_NET_USER, TANZU_NET_PASSWORD, and TANZU_NET_REFRESH_TOKEN need to be exported from shell before executing this script
KUBERNETES_CONTEXT=default
# Namespace where tap install will be deployed
NAMESPACE=tap-install
# Log file
OUT="./try-tap.log"
KAPP_VERSION="v0.39.0"
YTT_VERSION="v0.36.0"
IMGPKG_VERSION="v0.17.0"
KBLD_VERSION="v0.30.0"
KUBECTL_VERSION=v1.22.0
# TANZU VARIABLES TO DOWNLOAD STUFF
# To Find TANZU_CLI_URL
# 1. Go to network.pivotal.io
# 2. Login and search for Tanzu Application Platform
# 3. Select a release and click on tanzu-cli
# 4. Click the "i" icon and copy the path in the "API Download" box and set TANZU_CLI_URL=to that
TANZU_CLI_URL="https://network.pivotal.io/api/v2/products/tanzu-application-platform/releases/941562/product_files/1040320/download"
# To Find TANZU_KP_URL
# 1. Go to network.pivotal.io
# 2. Login and search for Tanzu Build Service
# 3. Select a release and click the "i" icon next to kp-linux and copy the path in the "API Download" box and set TANZU_KP_URL=to that
TANZU_KP_URL="https://network.pivotal.io/api/v2/products/build-service/releases/925788/product_files/1000629/download"
# TBS VERSON to use
TBS_VERSION="1.2.2" # Make an option

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
install_docker
install_kubectl $KUBECTL_VERSION
install_tanzu_cli "$TANZU_CLI_URL" "$TANZU_NET_REFRESH_TOKEN"
install_helm
install_kp "$TANZU_KP_URL" "$TANZU_NET_REFRESH_TOKEN"

cfg_tanzu_net "$TANZU_NET_USER" "$TANZU_NET_PASSWORD"

### Set up Kubernetes environment
install_k3s
env "PATH=$PATH" kubectl config set-context ${KUBERNETES_CONTEXT}
echo '' >>~/.bashrc
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

### Set LOCAL_EXTERNAL_IP
LOCAL_EXTERNAL_IP=""
while [ "$LOCAL_EXTERNAL_IP" == "" ] || [ "$LOCAL_EXTERNAL_IP" == "<pending>" ]
do
        sleep 1
        LOCAL_EXTERNAL_IP=$(kubectl get svc traefik -n kube-system | grep traefik | awk '{print $4}')
        info "LOCAL_EXTERNAL_IP: $LOCAL_EXTERNAL_IP"
done

### Change kubeconfig to use LOCAL_EXTERNAL_IP
sed -i "s/127.0.0.1/$LOCAL_EXTERNAL_IP/g" ~/.kube/config

### Install kapp controller
info "Installing kapp controller"
kapp deploy --yes -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml
# Setup package repo
kubectl create namespace tap-install
kubectl create secret docker-registry tap-registry -n tap-install --docker-server='registry.pivotal.io' --docker-username=$TANZU_NET_USER --docker-password=$TANZU_NET_PASSWORD
kapp deploy --yes -a tap-package-repo -n tap-install -f ./manifests/tap-package-repo.yaml
sleep 10
tanzu package repository list -n tap-install
info "Done installing kapp controller"

## Install Cloud Native Runtimesl
info "Installing CNR"
sed -i "s/TANZU-NET-USER/$TANZU_NET_USER/g" values/cnr-values.yaml
sleep 1
sed -i "s/TANZU-NET-PASSWORD/$TANZU_NET_PASSWORD/g" values/cnr-values.yaml
sleep 1
tanzu package install cloud-native-runtimes -p cnrs.tanzu.vmware.com -v 1.0.1 -n tap-install -f values/cnr-values.yaml --wait=false
info "waiting 60 seconds"
sleep 60
kubectl get svc envoy -n contour-external -o yaml | yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.annotations, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields, .spec.healthCheckNodePort, .spec.clusterIP, .spec.clusterIPs, .spec.ports[0].nodePort, .spec.ports[1].nodePort)' - > manifests/svc_envoy.yaml
sleep 1
sed -i "s/port: 80/port: 8080/g" manifests/svc_envoy.yaml
sleep 1
sed -i "s/ name: envoy/ name: envoy-8080/g" manifests/svc_envoy.yaml
sleep 1
kubectl apply -f manifests/svc_envoy.yaml
info "Check envoy error message"

## Install flux and app accelerator
info "Installing flux"
kapp deploy --yes -a flux -f https://github.com/fluxcd/flux2/releases/download/v0.15.0/install.yaml
sleep 1
kubectl delete -n flux-system networkpolicies --all
info "Installing app accelerator ..."
sed -i "s/TANZU-NET-USER/$TANZU_NET_USER/g" values/app-accelerator-values.yaml
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
sed -i "s/harbor.external.ip/$LOCAL_EXTERNAL_IP/g" values/harbor-values.yaml
helm install tap-harbor harbor/harbor -n harbor --values values/harbor-values.yaml
# Wait for harbor service to have external ip and then change registries
# May delete if not needed
HARBOR_SVC=""
while [ "$HARBOR_SVC" == "" ] || [ "$HARBOR_SVC" == "<pending>" ]
do
        sleep 1
        HARBOR_SVC=$(kubectl get svc harbor -n harbor | grep harbor | awk '{print $4}')
        info "HARBOR_SVC_IP: $HARBOR_SVC"
done
sed -i "s/harbor.external.ip/$LOCAL_EXTERNAL_IP/g" manifests/registries.yaml
sed -i "s/harbor.external.ip/$LOCAL_EXTERNAL_IP/g" manifests/daemon.json
cat manifests/daemon.json > /etc/docker/daemon.json
# Restart k3sE and docker
info "Add insecure registry and restart"
cp manifests/registries.yaml /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s
sudo systemctl restart docker

# Install TBS
info "Installing Tanzu Build Service ..."
# Login to local reg
info "Logging in to harbor ${LOCAL_EXTERNAL_IP}:8085"
HARBOR_LOGIN=$(sudo docker login ${LOCAL_EXTERNAL_IP}:8085 | grep Login)
info "Harbor Login Status: $HARBOR_LOGIN"
while [ "$HARBOR_LOGIN" != "Login Succeeded" ]
do
  info "Trying to login to harbor again"
  sleep 5
  HARBOR_LOGIN=$(sudo docker login ${LOCAL_EXTERNAL_IP}:8085 | grep Login)
  info "Status: $HARBOR_LOGIN"
done

# Login to pivotal reg
info "Logging in to tanzu registry"
docker login registry.pivotal.io -u "$TANZU_NET_USER" -p "$TANZU_NET_PASSWORD"
# Copy image from piv to local
info "Copying image from registry.pivotal.io/build-service/bundle:${TBS_VERSION} to ${LOCAL_EXTERNAL_IP}:8085/library/build-service"
imgpkg copy -b "registry.pivotal.io/build-service/bundle:${TBS_VERSION}" --to-repo "${LOCAL_EXTERNAL_IP}:8085/library/build-service"
# Download image from repo
info "Pulling image from ${LOCAL_EXTERNAL_IP}:8085/library/build-service:${TBS_VERSION}"
imgpkg pull -b "${LOCAL_EXTERNAL_IP}:8085/library/build-service:${TBS_VERSION}" -o /tmp/bundle
# Deploy
ytt -f /tmp/bundle/values.yaml -f /tmp/bundle/config/ -v docker_repository="${LOCAL_EXTERNAL_IP}:8085/library/build-service" -v docker_username='admin' -v docker_password='Harbor12345' -v no_proxy=${LOCAL_EXTERNAL_IP} | kbld -f /tmp/bundle/.imgpkg/images.yml -f- | kapp deploy -a tanzu-build-service -f- -y --wait-timeout 45m0s
# Don't know if needed yet
kubectl apply -f manifests/roles.yaml
# Have to get the output as there is a timeout ... so using dry-run-with-image-upload
kp import -f manifests/descriptor.yaml --registry-verify-certs=false --dry-run-with-image-upload --output yaml > manifests/build-stuff.yaml
kubectl apply -f manifests/build-stuff.yaml
# Kp command to see builders
kp clusterbuilder list

echo "Done with installing TAP via try-tap ..."
echo ""
echo "Check out the tap components in your browser"
echo "--------------------------------------------"
echo "Accelerator: http://${LOCAL_EXTERNAL_IP}:8081"
echo "App Live View: https://${LOCAL_EXTERNAL_IP}:5112"
echo "Harbor: http://${LOCAL_EXTERNAL_IP}:8085 user:admin password: Harbor12345"
echo ""
echo "Please try the guided demo at [link to go walk through]"