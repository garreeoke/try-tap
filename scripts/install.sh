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
install_kubectl $KUBECTL_VERSION
install_tanzu_cli "$TANZU_NET_REFRESH_TOKEN" "$TANZU_CLI_VERSION"
install_helm
cfg_tanzu_net

#detect_endpoint
#generate_passwords
#update_endpoint
#create_spin_endpoint

### Set up Kubernetes environment
install_k3s
env "PATH=$PATH" kubectl config set-context ${KUBERNETES_CONTEXT}
echo '' >>~/.bashrc
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# Install kapp controller
echo "Installing kapp controller"
kapp deploy -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml
# Setup package repo
kubectl create namespace tap-install
kubectl create secret docker-registry tap-registry -n tap-install --docker-server='registry.pivotal.io' --docker-username=$TANZU_NET_USER --docker-password=$TANZU_NET_PASSWORD
kapp deploy -y -a tap-package-repo -n tap-install -f ./manifests/tap-package-repo.yaml
tanzu package repository list -n tap-install

rm -rf cli

# Install Cloud Native Runtimes
info "Installing CNR"
tanzu package install cloud-native-runtimes -p cnrs.tanzu.vmware.com -v 1.0.1 -n tap-install -f values/cnr-values.yaml --wait=false
# Install flux and app accelerator
info "Installing flux"
kapp deploy -a flux -f https://github.com/fluxcd/flux2/releases/download/v0.15.0/install.yaml
info "Installing app accelerator ..."
tanzu package install app-accelerator -p accelerator.apps.tanzu.vmware.com -v 0.2.0 -n tap-install -f values/app-accelerator-values.yaml
info "Installing sample accelerators ..."
kubectl apply -f sample-accelerators-0-2.yaml
# Install app live view
info "Installing app live view ..."
tanzu package install app-live-view -p appliveview.tanzu.vmware.com -v 0.1.0 -n tap-install -f values/app-live-view-values.yaml
tanzu package installed list -n tap-install
info "DONE"
exit 0


# Install harbor
info "Installing harbor ..."

# Install TBS
info "Installing Tanzu Build Service"