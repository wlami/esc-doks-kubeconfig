#!/usr/bin/env bash
# Removes every billable resource, then the ESC environments.
source "$(dirname "$0")/common.sh"
cd "$ROOT/infra"

pulumi env run "$ACCESS_ENV" -- pulumi destroy --yes
pulumi stack rm dev --yes 2>/dev/null || true
pulumi env rm "$CLUSTER_ENV" --yes 2>/dev/null || true
pulumi env rm "$ACCESS_ENV" --yes 2>/dev/null || true
echo "Clean. Confirm at https://cloud.digitalocean.com/kubernetes/clusters"
