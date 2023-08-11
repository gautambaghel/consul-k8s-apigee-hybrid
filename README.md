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

### (Optional step) Override Default Config

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

* (Optional step) Alternatively use [consul-k8s](https://github.com/hashicorp/consul-k8s) cli service to install Consul

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

* Configure the Apigee Remote service with auto injector

```sh
infra/apigee-remote.sh
```

* Create consul intention between counting and dashboard services

```sh
kubectl apply -f consul/intentions.yaml
```
* Expose the dashboard service and test the connection; visit [localhost:9002](localhost:9002)

```sh
kubectl port-forward svc/dashboard 9002:9002
```

* The services should be connected

![connected](images/connected.png)

### Apply the ext_authz filter

* The ext_authz filter will be applied on the httpbin

```sh
kubectl apply -f consul/ext_authz.yaml
```

* (Optional) To debug port forward and visit [localhost:19000](localhost:19000) > click config_dump > search for 'ext_authz'

```sh
kubectl port-forward deployment/httpbin 19000
```

* Expose the dashboard service and test the connection again; visit [localhost:9002](localhost:9002)

```sh
kubectl port-forward svc/dashboard 9002:9002
```

* The services should be disconnected

![disconnected](images/disconnected.png)

* After using the API key generated from Apigee [(follow guide here)](https://cloud.google.com/apigee/docs/api-platform/envoy-adapter/v2.0.x/operation#how-to-obtain-an-api-key) and pinging again the response should have Apigee headers

> **_NOTE:_** There might be a delay after creating the API key of ~2 mins. 

```sh
export KEY="PASTE_YOUR_KEY_HERE"
sed 's@APIGEE_API_KEY@'"$KEY"'@' app/dashboard.yaml
kubectl apply -f app/dashboard.yaml
```

![connected](images/connected_again.png)

```

### Clean up

This tool includes a script to automatically clean up the Apigee hybrid
runtime resources (without deleting the Apigee Organization).

```sh
infra/destroy-runtime-gke.sh
```
