#!/usr/bin/env bash

USAGE="Usage: $0"

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TOP_LEVEL="$DIR/../.."
CHARTS_DIR="${TOP_LEVEL}/.local/charts"

NAMESPACE=${NAMESPACE:-test-integration}

kubectl create namespace "${NAMESPACE}" > /dev/null 2>&1 || true

${DIR}/integration-cleanup.sh

charts=( fake-aws databases-ephemeral wire-server )

echo "updating recursive dependencies ..."
for chart in "${charts[@]}"; do
  "$DIR/update.sh" "$CHARTS_DIR/$chart"
done

echo "Installing charts..."

function printLogs() {
    echo "---- a command failed, attempting to print useful debug information..."
    echo "-------------------------------"
    echo "-------------------------------"
    echo "-------------------------------"
    echo ""
    kubectl -n ${NAMESPACE} get pods
    kubectl -n ${NAMESPACE} get pods | grep -v Running | grep -v Pending | grep -v Completed | grep -v STATUS | grep -v ContainerCreating | awk '{print $1}' | xargs -n 1 -I{} bash -c "printf '\n\n----LOGS FROM {}:\n'; kubectl -n ${NAMESPACE} logs --tail=30 {}" || true
    kubectl -n ${NAMESPACE} get pods | grep Pending | awk '{print $1}' | xargs -n 1 -I{} bash -c "printf '\n\n----DESCRIBE 'pending' {}:\n'; kubectl -n ${NAMESPACE} describe pod {}" || true
}

trap printLogs ERR

FEDERATION_DOMAIN="$NAMESPACE.svc.cluster.local"

for chart in "${charts[@]}"; do
    kubectl -n ${NAMESPACE} get pods
    valuesfile="${DIR}/../helm_vars/${chart}/values.yaml"
    if [ -f "$valuesfile" ]; then
        option="-f $valuesfile"
    else
        option=""
    fi
    # default is 5m but may not be enough on a fresh install including cassandra migrations
    TIMEOUT=10m
    set -x
    helm upgrade --install --namespace "${NAMESPACE}" "${NAMESPACE}-${chart}" "${CHARTS_DIR}/${chart}" \
        $option \
        --set brig.config.optSettings.setFederationDomain="$FEDERATION_DOMAIN" \
        --set galley.config.settings.federationDomain="$FEDERATION_DOMAIN" \
        --wait \
        --timeout "$TIMEOUT"
    set +x
done

# wait for fakeSNS to create resources. TODO, cleaner: make initiate-fake-aws-sns a post hook. See cassandra-migrations chart for an example.
resourcesReady() {
    SNS_POD=$(kubectl -n "${NAMESPACE}" get pods | grep fake-aws-sns | grep Running | awk '{print $1}')
    kubectl -n "${NAMESPACE}" logs "$SNS_POD" -c initiate-fake-aws-sns | grep created
}
until resourcesReady; do echo 'waiting for SNS resources'; sleep 1; done

kubectl -n ${NAMESPACE} get pods

echo "done"
