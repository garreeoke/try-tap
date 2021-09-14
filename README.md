Try-Tap 

Install components to try out Tanzu Application Platform

git clone https://github.com/garreeoke/try-tap.git -b beta1

Export variables before running script:
export TANZU_NET_USER=your tanzu net user
export TANZU_NET_PASSWORD=your tanzu net password
export TANZU__REFRESH_TOKEN=""

Open firewall if on public cloud ports:
80, 443, 5112, 8080, 8081, 8082, 8083, 8084

Still can't figure out harbor

kubectl get svc -n accelerator-system acc-ui-server -o yaml \
| yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.annotations, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields)' -