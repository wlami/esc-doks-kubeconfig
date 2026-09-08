#!/usr/bin/env bash
# Creates the do-access environment WITHOUT the token in it.
# You add the token yourself afterwards, so it never passes through a transcript.
source "$(dirname "$0")/common.sh"

pulumi env init "$ACCESS_ENV" 2>/dev/null || echo "exists: $ACCESS_ENV"
pulumi env edit --file "$ROOT/esc/do-access.yaml" "$ACCESS_ENV"

cat <<EOF

Now run this yourself (it is the only place the PAT appears):

  pulumi env set $ACCESS_ENV do.token <YOUR_DO_PAT> --secret

Verify with:
  pulumi env run $ACCESS_ENV -- doctl account get
EOF
