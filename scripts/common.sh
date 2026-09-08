#!/usr/bin/env bash
set -euo pipefail
: "${PULUMI_ORG:?set PULUMI_ORG, e.g. export PULUMI_ORG=demo}"
ESC_PROJECT=esc-doks-demo
ACCESS_ENV="${PULUMI_ORG}/${ESC_PROJECT}/do-access"
CLUSTER_ENV="${PULUMI_ORG}/${ESC_PROJECT}/doks-dev"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
