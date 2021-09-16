#!/bin/bash

function log() {
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  ORANGE='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
  LEVEL=$1
  MSG=$2
  case $LEVEL in
  "INFO") HEADER_COLOR=$GREEN MSG_COLOR=$NS ;;
  "WARN") HEADER_COLOR=$ORANGE MSG_COLOR=$NS ;;
  "KUBE") HEADER_COLOR=$ORANGE MSG_COLOR=$CYAN ;;
  "ERROR") HEADER_COLOR=$RED MSG_COLOR=$NS ;;
  esac
  sudo printf "${HEADER_COLOR}[%-5.5s]${NC} ${MSG_COLOR}%b${NC}" "${LEVEL}" "${MSG}"
  sudo printf "$(date +"%D %T") [%-5.5s] %b" "${LEVEL}" "${MSG}" >>"$OUT"
}

function info() {
  log "INFO" "$1\n"
}

function warn() {
  log "WARN" "$1\n"
}

function error() {
  log "ERROR" "$1\n" && exit 1
}

function handle_generic_kubectl_error() {
  error "Error executing command:\n$ERR_OUTPUT"
}

function exec_kubectl_mutating() {
  log "KUBE" "$1\n"
  ERR_OUTPUT=$({ $1 >>"$OUT"; } 2>&1)
  EXIT_CODE=$?
  [[ $EXIT_CODE != 0 ]] && $2
}

install_k3s () {
  info "--- Installing K3s ---"
  #curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -
  curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -s - --docker
  info "pausing for 10 seconds"
  sleep 10
  cp -R /etc/rancher/k3s/k3s.yaml ~/.kube/config
  chmod 644 ~/.kube/config
  info " --- END K3s --- "
  echo ""
  sleep 5
}

## Install helm
install_helm () {
  info "--- Installing helm ---"
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
  info " --- END helm --- "
  echo ""
  sleep 2
}

## Configure tanzunet
cfg_tanzu_net () {
  sed -i "s/TANZU-NET-USER/$1/g" values/*.yaml
  sed -i "s/TANZU-NET-PASSWORD/$2/g" values/*.yaml
}

## Install carvel tools
install_kapp () {
  info " --- Installing kapp --- "
  # $1 is the release string: v0.39.0
  info "Installing kapp $1"
  wget https://github.com/vmware-tanzu/carvel-kapp/releases/download/$1/kapp-linux-amd64
  sudo chmod +x ./kapp-linux-amd64
  sudo mv -f ./kapp-linux-amd64 /usr/local/bin/kapp
  # Execute kapp command
  kapp -v
  info " --- END kapp --- "
  echo ""
  sleep 2
}

install_ytt () {
  info " --- Installing ytt --- "
  wget https://github.com/vmware-tanzu/carvel-ytt/releases/download/$1/ytt-linux-amd64
  sudo chmod +x ./ytt-linux-amd64
  sudo mv -f ./ytt-linux-amd64 /usr/local/bin/ytt
  ytt --version
  info " --- END ytt --- "
  echo ""
  sleep 2
}

install_imgpkg () {
  info " --- Installing imgpkg --- "
  wget https://github.com/vmware-tanzu/carvel-imgpkg/releases/download/$1/imgpkg-linux-amd64
  sudo chmod +x ./imgpkg-linux-amd64
  sudo mv -f ./imgpkg-linux-amd64 /usr/local/bin/imgpkg
  imgpkg -v
  info " --- END imgpkg --- "
  echo ""
  sleep 2
}

install_kbld () {
  info " --- Installing kbld --- "
  #$1 is the release string: v0.30.0
  wget https://github.com/vmware-tanzu/carvel-kbld/releases/download/$1/kbld-linux-amd64
  sudo chmod +x ./kbld-linux-amd64
  sudo mv -f ./kbld-linux-amd64 /usr/local/bin/kbld
  kbld --version
  info " --- END kbld --- "
  echo ""
  sleep 2
}

install_kubectl () {
  info " --- Installing kubectl --- "
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo chmod +x ./kubectl
  sudo mv -f ./kubectl /usr/local/bin/kubectl
  info " --- END kubectl --- "
  echo ""
  sleep 2
}

install_tanzu_cli () {
  info " --- Installing tanzu cli --- "
  # Get access token
  ACCESS_TOKEN=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d "$(generate_token_data $2)" | jq '.access_token')
  # Issue here ... seems this URL changes over time ... may have to be able to find it
  wget -O tanzu-cli-bundle-linux-amd64.tar --header="Authorization: Bearer $ACCESS_TOKEN" "$1"
  tar -xvf tanzu-cli-bundle-linux-amd64.tar
  rm -f tanzu-cli-bundle-linux-amd64.tar
  VERSION=$(ls cli/core | grep v)
  sudo install cli/core/${VERSION}/tanzu-core-linux_amd64 /usr/local/bin/tanzu
  tanzu plugin clean
  tanzu plugin install -v $VERSION --local cli package
  tanzu package version
  info " --- End tanzu cli --- "
  echo ""
  sleep 2
}

install_kp () {
    info " --- Installing kp cli --- "
    ACCESS_TOKEN=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d "$(generate_token_data $2)" | jq '.access_token')
    wget -O kp --header="Authorization: Bearer $ACCESS_TOKEN" $1
    sudo chmod +x ./kp
    sudo mv -f ./kp /usr/local/bin/kp
    info " --- End kp cli --- "v
    echo ""
    sleep 2
}

generate_token_data() {
  cat <<EOF
{
  "refresh_token": "$1"
}
EOF
}

install_yq () {
  info " --- Installing yq --- "
  sudo curl -sfL https://github.com/mikefarah/yq/releases/download/v4.7.1/yq_linux_amd64 -o /usr/local/bin/yq
  sudo chmod +x /usr/local/bin/yq
  if [[ ! -e "/usr/local/bin/yq" ]]; then
    error "failed to install yq - please manually install https://github.com/mikefarah/yq/"
    exit 1
  fi
  info " --- End yp --- "
  echo ""
  sleep 2
}

install_jq () {
  info " --- Installing jq --- "
  if ! jq --help > /dev/null 2>&1; then
    # only try installing if a Debian system
    if apt-get -v > /dev/null 2>&1; then
      info "Using apt-get to install jq"
      sudo apt-get update && sudo apt-get install -y jq
    else
      error "ERROR: Unsupported OS! Cannot automatically install jq. Please try install jq first before rerunning this script"
      exit 2
    fi
  fi
  info " --- End jq --- "
  echo ""
  sleep 2
}

install_unzip () {
  info " --- Installing unzip --- "
  if ! unzip --help > /dev/null 2>&1; then
    # only try installing if a Debian system
    if apt-get -v > /dev/null 2>&1; then
      info "Using apt-get to install unzip"
      sudo apt-get update && sudo apt-get install -y unzip
    else
      error "ERROR: Unsupported OS! Cannot automatically install unzip. Please try install jq first before rerunning this script"
      exit 2
    fi
  fi
  info " --- End unzip --- "
  echo ""
  sleep 2
}

install_docker () {
  info " --- Installing docker --- "
  if ! docker --help > /dev/null 2>&1; then
    # only try installing if a Debian system
    if apt-get -v > /dev/null 2>&1; then
      info "Using apt-get to install docker"
      sudo apt-get update && sudo apt-get install -y docker.io
    else
      error "ERROR: Unsupported OS! Cannot automatically install docker. Please try install jq first before rerunning this script"
      exit 2
    fi
  fi
  info " --- End docker --- "
  echo ""
  sleep 2
}

restart_k3s (){
  info "Restarting k3s"
  /usr/local/bin/k3s-killall.sh
  sudo systemctl restart k3s
}
