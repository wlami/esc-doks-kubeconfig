#!/usr/bin/env bash
# Creates the DOKS cluster. The DO token comes from ESC, not from your shell.
source "$(dirname "$0")/common.sh"
cd "$ROOT/infra"

[ -d node_modules ] || npm install --silent
pulumi stack select dev 2>/dev/null || pulumi stack init dev
pulumi env run "$ACCESS_ENV" -- pulumi up --yes
pulumi stack output
