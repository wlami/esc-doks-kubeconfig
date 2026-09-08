#!/usr/bin/env bash
# Creates the doks-dev environment: the exec-plugin kubeconfig.
source "$(dirname "$0")/common.sh"

pulumi env init "$CLUSTER_ENV" 2>/dev/null || echo "exists: $CLUSTER_ENV"
pulumi env edit --file "$ROOT/esc/doks-dev.yaml" "$CLUSTER_ENV"
echo
echo "Try it:"
echo "  pulumi env run $CLUSTER_ENV -- kubectl get nodes"
