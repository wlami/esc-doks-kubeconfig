#!/usr/bin/env bash
# Appends an allow policy to an EXISTING GitHub OIDC issuer, leaving every
# other policy on it untouched.
#
# Use this when your org already has https://token.actions.githubusercontent.com
# registered (only one issuer per URL per org is allowed) and it belongs to
# someone else, so you must not take it over.
#
# Usage: PULUMI_ORG=demo SUBJECT='repo:me@1/repo@2:*' ./scripts/05-add-oidc-policy.sh
source "$(dirname "$0")/common.sh"
: "${SUBJECT:?set SUBJECT to the sub claim from your workflow log}"

ISSUER_ID=$(pulumi api List_orgs_oidc_issuers -F orgName="$PULUMI_ORG" \
  | python3 -c "
import sys,json
for i in json.load(sys.stdin)['oidcIssuers']:
    if 'token.actions.githubusercontent.com' in i['url']: print(i['id']); break
")
[ -n "$ISSUER_ID" ] || { echo "No GitHub issuer in $PULUMI_ORG. Use the oidc/ project instead."; exit 1; }

TMP=$(mktemp -d)
pulumi api GetAuthPolicy -F orgName="$PULUMI_ORG" -F issuerId="$ISSUER_ID" > "$TMP/before.json"
POLICY_ID=$(python3 -c "import json;print(json.load(open('$TMP/before.json'))['id'])")
echo "issuer $ISSUER_ID / policy doc $POLICY_ID"
echo "backup: $TMP/before.json"

python3 - "$TMP" "$SUBJECT" "$PULUMI_ORG" <<'EOF'
import json,sys
tmp,sub,org=sys.argv[1],sys.argv[2],sys.argv[3]
cur=json.load(open(f"{tmp}/before.json"))
pol=[dict(p) for p in cur["policies"]]          # carried over verbatim
if any(p.get("rules",{}).get("sub")==sub for p in pol):
    print("already present, nothing to do"); sys.exit(1)
pol.append({"decision":"allow","tokenType":"organization",
            "authorizedPermissions":["standard"],
            "rules":{"aud":f"urn:pulumi:org:{org}","sub":sub}})
json.dump({"policies":pol}, open(f"{tmp}/patch.json","w"), indent=2)
print(f"appending 1 policy to {len(pol)-1} existing")
EOF

pulumi api UpdateAuthPolicy -F orgName="$PULUMI_ORG" -F policyId="$POLICY_ID" \
  --input "$TMP/patch.json" > /dev/null
pulumi api GetAuthPolicy -F orgName="$PULUMI_ORG" -F issuerId="$ISSUER_ID" > "$TMP/after.json"

python3 - "$TMP" <<'EOF'
import json,sys
tmp=sys.argv[1]
b=json.load(open(f"{tmp}/before.json")); a=json.load(open(f"{tmp}/after.json"))
k=lambda p:p.get("rules",{}).get("sub"); am={k(p):p for p in a["policies"]}
ok=True
for p in b["policies"]:
    s=k(p); same = s in am and json.dumps(p,sort_keys=True)==json.dumps(am[s],sort_keys=True)
    print(("  OK  untouched  " if same else "  !!  CHANGED   ")+str(s)); ok&=same
print("\nVERDICT:", "pre-existing policies intact" if ok else "REGRESSION - restore from before.json")
EOF
