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
apigee/apigee-remote-service-cli provision --organization $ORG --environment $ENV_NAME --runtime $RUNTIME --namespace $APIGEE_NAMESPACE --token $TOKEN --verbose > apigee/config.yaml

# configure apigee-envoy-adapter deployment yaml
export SECRET_NAME="${ORG}-${ENV_NAME}-policy-secret"
yq eval '.spec.template.spec.volumes[1].secret.secretName = env(SECRET_NAME)' -i apigee/apigee-envoy-adapter.yaml
yq eval '.spec.template.metadata.labels.org = env(ORG)' -i apigee/apigee-envoy-adapter.yaml
yq eval '.spec.template.metadata.labels.env = env(ENV_NAME)' -i apigee/apigee-envoy-adapter.yaml

# configure apigee-envoy-adapter service yaml
yq eval '.metadata.labels.org = env(ORG)' -i apigee/apigee-envoy-adapter-svc.yaml
yq eval '.metadata.labels.env = env(ENV_NAME)' -i apigee/apigee-envoy-adapter-svc.yaml

echo "🔧 Applying deployment, configmap and secrets for the Apigee remote service"
# Apply the deployment, svc, configmap, secret and service account in apigee namespace
kubectl apply -f apigee/

# Deploy the curl service
echo "🔧 Deploying the curl service"
kubectl apply -f app/curl.yaml

# Restart httpbin pod for Consul
echo "🔧 Restarting the httpbin service"
kubectl delete pod -l app=httpbin
