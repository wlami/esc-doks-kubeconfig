#!/usr/bin/env bash
# The punchline: two kubeconfigs for the same cluster, side by side.
source "$(dirname "$0")/common.sh"
cd "$ROOT/infra"
CLUSTER_ID="$(pulumi stack output clusterId)"

hr() { printf '\n\033[1m%s\033[0m\n' "$*"; }

hr "1. The kubeconfig most teams ship (doctl kubeconfig show)"
pulumi env run "$ACCESS_ENV" -- \
  doctl kubernetes cluster kubeconfig show "$CLUSTER_ID" 2>/dev/null \
  | sed -n '/^users:/,$p' | sed 's/\(token: \).*/\1<REDACTED>/'
echo "  ^ a literal bearer token, copied to every laptop and CI runner."
echo "    When it expires, someone re-runs a script."

hr "2. The kubeconfig ESC vends"
pulumi env run "$CLUSTER_ENV" -- sh -c 'sed -n "/^users:/,\$p" "$KUBECONFIG"'
echo "  ^ no credential at all. kubectl execs doctl, which mints and renews."

hr "3. Credentials embedded in the vended file"
n=$(pulumi env run "$CLUSTER_ENV" -- sh -c \
      'grep -cE "^[[:space:]]*(token|client-key-data|client-certificate-data):" "$KUBECONFIG" || true')
echo "  $n"

hr "4. It works"
pulumi env run "$CLUSTER_ENV" -- kubectl get nodes -o wide

hr "5. Lifetime of the token doctl just minted"
CACHE="$HOME/Library/Application Support/doctl/cache/exec-credential/$CLUSTER_ID.json"
[ -f "$CACHE" ] || CACHE="$HOME/.cache/doctl/exec-credential/$CLUSTER_ID.json"
if [ -f "$CACHE" ]; then
  python3 -c "
import json,sys,datetime
d=json.load(open(sys.argv[1]))['status']
e=datetime.datetime.fromisoformat(d['expirationTimestamp'].replace('Z','+00:00'))
print('  expires:', d['expirationTimestamp'], '(in', str(e-datetime.datetime.now(datetime.timezone.utc)).split('.')[0]+')')
" "$CACHE"
  echo "  cached at: $CACHE"
  echo
  echo "  NOTE: 7 days, the same lifetime as the static token. The exec plugin"
  echo "  buys automatic RENEWAL, not a shorter-lived credential. See the"
  echo "  'What this does and does not buy you' section of the README."
else
  echo "  (no cache file yet; run kubectl once first)"
fi
