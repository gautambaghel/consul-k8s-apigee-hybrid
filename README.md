# consul-k8s-apigee-hybrid

![ext_authz](images/arch.png)

## Apigee hybrid used for ext_authz with Consul Service Mesh

Following instructions are taken from the [quickstart repository here](https://github.com/apigee/devrel/tree/main/tools/hybrid-quickstart) please refer to this repo for issues and further assistance.

### Select a GCP project

* Select the GCP project to install Apigee hybrid

```sh
export PROJECT_ID=xxx
gcloud config set project $PROJECT_ID
gcloud auth login
gcloud auth application-default login
```

### (Optional) Override Default Config

* The following environment variables are set by default, export them to override the default values if needed.

```sh
# GCP region and zone for the runtime
export REGION='us-west1'
export ZONE='us-west1-a,us-west1-b,us-west1-c'

# Networking
export NETWORK='apigee-hybrid'
export SUBNET='apigee-us-west1'

# Runtime GKE cluster
export GKE_CLUSTER_NAME='apigee-hybrid'
export GKE_CLUSTER_MACHINE_TYPE='e2-standard-4'

# Apigee Env Config
export ENV_NAME='env'
export ENV_GROUP_NAME='envgroup'
```

### Initialize the Apigee hybrid runtime on a GKE cluster

After the configuration is done run the following command to initialize you
Apigee hybrid organization and runtime. ***This typically takes between 15 and
20min.***

```sh
infra/initialize-runtime-gke.sh
```

* Apigee hybrid config files are generated at [infra/hybrid-files/overrides.yaml](infra/hybrid-files/overrides.yaml)

### Install Consul in k8s

* This example needs Consul version > 1.16 to work

```sh
export CONSUL_LICENSE="paste-your-consul-license-here"
kubectl create ns consul
kubectl create secret generic consul-enterprise-license --from-literal=key=$CONSUL_LICENSE -n consul
helm install consul hashicorp/consul --namespace consul --values consul/values.yaml
```

* (Optional) Alternatively use [consul-k8s](https://github.com/hashicorp/consul-k8s) cli service to install Consul

```sh
brew install consul-k8s # change based on the OS
kubectl create ns consul
kubectl create secret generic consul-enterprise-license --from-literal=key=$CONSUL_LICENSE -n consul
consul-k8s install -namespace consul -f consul/values.yaml
```

* Ensure Consul services are healthy

```sh
kubectl get pods -n consul
```

### Configure Apigee Envoy adapter and deploy sample services

Following instructions are taken from [this guide](https://cloud.google.com/apigee/docs/api-platform/envoy-adapter/v2.0.x/example-hybrid) please refer there for issues and further assistance.

* Configure the Apigee Remote service

```sh
infra/apigee-remote.sh
```

* Configure Consul

```sh
# Configure the apigee-envoy-adapter service as grpc in Consul using Service Default
kubectl apply -f consul/proxy_service_default.yaml

# Create consul intentions as such curl -> httpbin & httpbin -> apigee-envoy-adapter
kubectl apply -f consul/intentions.yaml

# Deploy the 2 services
kubectl apply -f app/
```

* Ping the httpbin service from curl service

```sh
kubectl exec -it deployment/curl -- /bin/sh
curl -i httpbin.default.svc.cluster.local/headers
```

* The response should be HTTP/1.1 200 OK

```sh
HTTP/1.1 200 OK
server: envoy
date: Thu, 99 XX 20XX XX:XX:XX GMT
content-type: application/json
content-length: 2225
access-control-allow-origin: *
access-control-allow-credentials: true
x-envoy-upstream-service-time: 28

{
    "headers": {
        "Accept": "*/*", 
        "Host": "httpbin.default.svc.cluster.local", 
        "User-Agent": "curl/8.2.0", 
        "X-Envoy-Auth-Failure-Mode-Allowed": "true", 
        "X-Envoy-Expected-Rq-Timeout-Ms": "15000", 
        "X-Forwarded-Client-Cert": "--cert-redacted--"
    }
}
```

### Apply the ext_authz filter

* The ext_authz filter will be applied on the httpbin

```sh
kubectl apply -f consul/ext_authz.yaml
```

* (Optional) To debug port forward and visit [localhost:19000](localhost:19000) > click config_dump > search for 'ext_authz'

```sh
kubectl port-forward deployment/httpbin 19000
```

* Ping the httpbin service from curl service again

```sh
kubectl exec -it deployment/curl -- /bin/sh
curl -i httpbin.default.svc.cluster.local/headers
```

* The response should be HTTP/1.1 403 Forbidden

```sh
HTTP/1.1 403 Forbidden
date: Thu, 99 XX 20XX XX:XX:XX GMT
server: envoy
content-length: 0
x-envoy-upstream-service-time: 3
```

* After using the API key generated from Apigee [(follow guide here)](https://cloud.google.com/apigee/docs/api-platform/envoy-adapter/v2.0.x/operation#how-to-obtain-an-api-key) and pinging again the response should have Apigee headers

> **_NOTE:_** There might be a delay after creating the API key of ~2 mins. 

```sh
curl -i httpbin.default.svc.cluster.local/headers -H "x-api-key: developer_client_key_goes_here"
```

```sh
HTTP/1.1 200 OK
server: envoy
date: Thu, 99 XX 20XX XX:XX:XX GMT
content-type: application/json
content-length: 2727
access-control-allow-origin: *
access-control-allow-credentials: true
x-envoy-upstream-service-time: 22
{
    "headers": {
        "Accept": "*/*", 
        "Host": "httpbin.default.svc.cluster.local", 
        "User-Agent": "curl/8.2.0", 
        "X-Api-Key": "developer_client_key_goes_here", 
        "X-Apigee-Accesstoken": "", 
        "X-Apigee-Api": "httpbin.default.svc.cluster.local", 
        "X-Apigee-Apiproducts": "httpbin-product", 
        "X-Apigee-Application": "httpbin-app", 
        "X-Apigee-Authorized": "true", 
        "X-Apigee-Clientid": "developer_client_key_goes_here", 
        "X-Apigee-Developeremail": "user@hashicorp.com", 
        "X-Apigee-Environment": "env", 
        "X-Apigee-Organization": "GCP_ORG_ID", 
        "X-Apigee-Scope": "", 
        "X-Envoy-Expected-Rq-Timeout-Ms": "15000",
        "X-Forwarded-Client-Cert": "--cert-redacted--"
    }
}
```

### Clean up

This tool includes a script to automatically clean up the Apigee hybrid
runtime resources (without deleting the Apigee Organization).

```sh
infra/destroy-runtime-gke.sh
```
