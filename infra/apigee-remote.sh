#!/bin/bash

set -e

QUICKSTART_ROOT="$( cd "$(dirname "$0")" || exit >/dev/null 2>&1 ; pwd -P )"
export QUICKSTART_ROOT

source "$QUICKSTART_ROOT/steps.sh"

echo "🔧 Setting the Apigee config params"
set_config_params

export APP_NAMESPACE="default"
echo "- App Namespace $APP_NAMESPACE"

export APIGEE_NAMESPACE="apigee"
echo "- Apigee Namespace $APIGEE_NAMESPACE"

export ORG=$PROJECT_ID
echo "- Apigee Org Name $ORG"

export RUNTIME="https://$ENV_GROUP_NAME.$DNS_NAME"
echo "- Apigee Runtime $RUNTIME"

export TOKEN=$(token)

OS_NAME=$(uname -s)

if [[ "$OS_NAME" == "Linux" ]]; then
    echo "- 🐧 Using Linux binaries"
    export APIGEE_OS_NAME='linux'
elif [[ "$OS_NAME" == "Darwin" ]]; then
    echo "- 🍏 Using macOS binaries"
    export APIGEE_OS_NAME='macOS'
    if ! [ -x "$(command -v timeout)" ]; then
    echo "Please install the timeout command for macOS. E.g. 'brew install coreutils'"
    exit 2
    fi
else
    echo "💣 Only Linux and macOS are supported at this time. You seem to be running on $OS_NAME."
    exit 2
fi

# Download the https://github.com/apigee/apigee-remote-service-cli
echo "🔧 Downloading the Apigee remote service"
export APIGEE_REMOTE_VERSION=${APIGEE_REMOTE_VERSION:-'2.1.1'}
curl -L https://github.com/apigee/apigee-remote-service-cli/releases/download/v$APIGEE_REMOTE_VERSION/apigee-remote-service-cli_${APIGEE_REMOTE_VERSION}_${APIGEE_OS_NAME}_64-bit.tar.gz > apigee-remote-service-cli.tar.gz
tar -xf apigee-remote-service-cli.tar.gz -C apigee/
rm apigee-remote-service-cli.tar.gz
apigee/apigee-remote-service-cli version

# Provision the Authz services
apigee/apigee-remote-service-cli provision --organization $ORG --environment $ENV_NAME --runtime $RUNTIME --namespace $APIGEE_NAMESPACE --token $TOKEN --insecure --verbose > apigee/config.yaml

echo "🔧 Applying configmap and secrets for the Apigee remote service"
# generate the configmap, secret and service account in apigee namespace
kubectl apply -f apigee/config.yaml

# generate the configmap, secret and service account in default namespace
echo "🔧 Applying configmap and secrets in the $APP_NAMESPACE namespace"
yq eval '.metadata.name = "apigee-remote-service-envoy"' -i apigee/config.yaml
yq eval 'select(.metadata.namespace == env(APIGEE_NAMESPACE)) | .metadata.namespace = env(APP_NAMESPACE)' -i "apigee/config.yaml"
kubectl apply -f apigee/config.yaml

# Deploy the dashboard and counting services
echo "🔧 Deploying the dashboard and counting services"
kubectl apply -f app/counting.yaml
kubectl apply -f app/dashboard.yaml

# Create Webhook injector for Apigee remote service
echo "🔧 Label $APP_NAMESPACE namespace to inject Apigee proxy sidecar"
kubectl label namespace $APP_NAMESPACE sidecar-injection=enabled --overwrite=true

echo "🔧 Create Webhook injector for Apigee remote service"
kubectl get namespace sidecar-injector >/dev/null 2>&1 || kubectl create namespace sidecar-injector
kubectl apply -f apigee/

# Restart httpbin pod for injector to attach itself
echo "Sleep for 30 seconds for injector pod to come up"
sleep 30
kubectl delete pod -l app=counting
