# kubectl access to DOKS that never expires on you

A minimal, runnable example: a DigitalOcean Kubernetes cluster whose kubeconfig
never goes stale, because it contains no credential at all.

Pulumi ESC vends the kubeconfig to a temp file; `kubectl` execs `doctl`, which
mints the token and silently renews it when it lapses. Nobody re-runs a script
on Monday morning.

Measured, not assumed: every claim below was verified against a live cluster,
and the section at the bottom says plainly what this does **not** buy you.

## The problem

`doctl` writes two different kinds of kubeconfig, and the difference is easy to
miss. From [`commands/kubernetes.go`](https://github.com/digitalocean/doctl/blob/main/commands/kubernetes.go):

```go
case remoteKubeconfigType == "token" && kubeconfigParams.expirySeconds > 0:
    // When expirySeconds is passed, token based auth should be used as
    // credentials should expire and not be renewed automatically
    local.AuthInfos[...] = &clientcmdapi.AuthInfo{ Token: remoteAuthInfo.Token }

case remoteKubeconfigType == "token" && kubeconfigParams.expirySeconds == 0:
    // Configure kubectl to call doctl to renew credentials automatically
    local.AuthInfos[...] = &clientcmdapi.AuthInfo{ Exec: &clientcmdapi.ExecConfig{
        Command: "doctl",
        Args: []string{"kubernetes", "cluster", "kubeconfig", "exec-credential",
                       "--version=v1beta1", "--context=default", clusterID},
    }}
```

**Static token.** A literal bearer token in the file. Default lifetime 7 days,
never renewed. This is what you get from:

- `doctl kubernetes cluster kubeconfig show <id>`
- the raw API, `GET /v2/kubernetes/clusters/{id}/kubeconfig`
- `doctl kubernetes cluster kubeconfig save --expiry-seconds N`
- the Pulumi DigitalOcean provider's `cluster.kubeConfigs[0].rawConfig` output

**Exec plugin.** No credential in the file. `kubectl` shells out to `doctl` via
the client-go [ExecCredential](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins)
protocol and gets a fresh token per call.

Teams usually end up on the first path without choosing it, most often by
exporting `rawConfig` as a stack output and passing it around. Then the token
expires every week and someone re-runs a script. The credential *shape* is the
bug, not the tooling.

## The mechanism

```
                  ┌──────────────────────────────────────┐
                  │ Pulumi ESC                            │
  infra stack ───▶│  doks-dev                             │
  (endpoint, CA,  │   ├─ fn::open::pulumi-stacks          │
   cluster id)    │   │    reads STABLE cluster facts     │
                  │   └─ files: KUBECONFIG                │
                  │        exec-plugin kubeconfig,        │
                  │        no token inside                │
                  │  do-access                            │
                  │   └─ DIGITALOCEAN_ACCESS_TOKEN        │
                  └───────────────┬──────────────────────┘
                                  │ pulumi env run
                                  ▼
                     $KUBECONFIG=/tmp/xxxx  (temp file)
                                  │
                          kubectl get nodes
                                  │  exec
                                  ▼
                      doctl ... exec-credential
                                  │  mints, ~short lifetime
                                  ▼
                            DOKS API server
```

Two ideas do the work:

1. **Split stable from volatile.** The cluster endpoint, CA certificate and id
   are stable for the life of the cluster, so ESC reads them from the infra
   stack. The token is volatile, so it is never stored anywhere and is minted
   per call. `infra/index.ts` deliberately does *not* export `rawConfig`.

2. **`files:` instead of `environmentVariables:`.** ESC writes the kubeconfig to
   a temp file and puts the *path* in `$KUBECONFIG`. `kubectl` and the Pulumi
   Kubernetes provider both honour `$KUBECONFIG`, so nothing else needs
   configuring, and no kubeconfig is ever persisted to a developer's disk.

The kubeconfig itself holds no credential, so there is nothing in it to expire
and nothing to redistribute. The DigitalOcean PAT lives in ESC: a single thing
to rotate instead of N laptops to chase.

## Prerequisites

- `pulumi` (3.150+), `kubectl`, `node` 18+
- `doctl` 1.168+ — `brew install doctl`
- A Pulumi organization and a DigitalOcean PAT with read/write scope

You do **not** need to run `doctl auth init`. ESC supplies
`DIGITALOCEAN_ACCESS_TOKEN`, which `doctl` picks up (its viper env prefix is
`DIGITALOCEAN`, so the `access-token` key maps to that variable).

## Walkthrough

```bash
export PULUMI_ORG=<your-org>

# 1. Create the access environment (no token in it yet).
./scripts/01-esc-access.sh

# 2. Add the PAT yourself. This is the only place it appears.
pulumi env set $PULUMI_ORG/esc-doks-demo/do-access do.token <YOUR_DO_PAT> --secret
pulumi env run $PULUMI_ORG/esc-doks-demo/do-access -- doctl account get

# 3. Create the cluster. The provider gets its token from ESC.
./scripts/02-up.sh

# 4. Create the kubeconfig environment.
./scripts/03-esc-cluster.sh

# 5. Use it.
pulumi env run $PULUMI_ORG/esc-doks-demo/doks-dev -- kubectl get nodes
```

Two things that will bite you if you deviate:

- **The ESC environments and the infra stack must live in the same Pulumi org.**
  `fn::open::pulumi-stacks` resolves `<project>/<stack>` within the environment's
  own org. If your default org differs from the one you create the environments
  in, `pulumi stack init <org>/<project>/<stack>` explicitly. A stack created in
  the wrong org cannot be moved with `pulumi stack rename` (ownership transfer is
  refused); use `pulumi stack export` / `import` into a correctly named stack, or
  the Transfer Stack button in the console.
- **`esc/do-access.yaml` ships a `REPLACE_ME` placeholder on purpose.** ESC
  validates interpolations at edit time, so `${do.token}` fails with
  `unknown property "do"` unless the key already exists. Apply the file first,
  then overwrite the placeholder with `pulumi env set ... --secret`.

`./scripts/04-demo.sh` prints both kubeconfigs for the same cluster side by
side: the `token:` stanza from `doctl kubeconfig show`, and the `exec:` stanza
ESC vends, followed by a working `kubectl get nodes` and the expiry timestamp of
the credential that was just minted.

## Teardown

```bash
./scripts/99-destroy.sh
```

Destroys the cluster, removes the stack, and deletes both ESC environments.

**Cost.** One `s-1vcpu-2gb` node, no HA control plane, no load balancer, no
registry: roughly $0.018/hour, so cents for a walkthrough. The DOKS control
plane is free on the standard tier. `destroyAllAssociatedResources: true` on the
cluster means `pulumi destroy` also removes load balancers and volumes the
cluster created for itself, which are the usual source of a surprise bill.
Verify at <https://cloud.digitalocean.com/kubernetes/clusters> afterwards.

## CI with no stored secrets

`.github/workflows/kubectl-via-esc.yml` closes the other half. GitHub mints an
OIDC token, `pulumi/auth-actions` exchanges it for a short-lived Pulumi token,
and `pulumi/esc-action` loads the same environment. There is no
`DIGITALOCEAN_ACCESS_TOKEN` in repository secrets and no kubeconfig in the repo.

Requires a one-time OIDC issuer registration in your Pulumi org
([docs](https://www.pulumi.com/docs/administration/access-identity/oidc-issuers/github/)).

## What this does and does not buy you

Worth being exact, because the obvious reading is too generous.

**What it fixes.** The kubeconfig never expires, because it holds no credential.
`doctl` mints one on demand and renews it transparently once it lapses. No
kubeconfig is copied between machines, none is committed, and none is written to
a developer's disk by this setup. Revoking the single PAT in ESC cuts off every
consumer at once.

**What it does not fix.** The token `doctl` mints is *also* a 7 day token, the
same lifetime as the static one, and `doctl` caches it on local disk:

```
~/Library/Application Support/doctl/cache/exec-credential/<cluster-id>.json
{"kind":"ExecCredential","status":{"token":"...","expirationTimestamp":"..."}}
```

So this is **automatic renewal, not credential minimization**. If your threat
model is "a laptop gets stolen", you have narrowed the window from *forever* to
*7 days*, not to minutes.

DigitalOcean makes you pick one or the other. `--expiry-seconds` gives you a
genuinely short-lived token, and `doctl` then deliberately writes the *static*
form, because a credential that is meant to expire should not silently renew:

```go
// When expirySeconds is passed, token based auth should be used as
// credentials should expire and not be renewed automatically
```

**Getting both.** Short-lived *and* auto-renewing needs a minting step that runs
on every open. An ESC [`fn::open::external`](https://www.pulumi.com/docs/esc/providers/external/)
adapter that calls `GET /v2/kubernetes/clusters/{id}/kubeconfig?expiry_seconds=600`
does this, at the cost of a service you host and secure. That adapter must
verify the inbound JWT (RS256 against Pulumi's JWKS, checking both `sub` and
`body_hash`), or anyone who learns the URL can mint cluster credentials. Out of
scope here; this repo is the 90% that takes an afternoon.

**Other limits.**

- ESC has **no DigitalOcean and no Kubernetes login provider**. Providers are
  `aws-login`, `azure-login`, `doppler-login`, `gcp-login`, `gh-login`,
  `infisical-login`, `snowflake-login`, `vault-login`. This example is assembled
  from `pulumi-stacks` + `files` + the `doctl` exec plugin.
- The **PAT is long-lived**. ESC has no DigitalOcean rotator (rotators cover
  `aws-iam`, `azure-app-secret`, `mysql`, `password`, `passphrase`, `postgres`,
  `snowflake-user`, `external`), so rotating it means a scheduled manual
  rotation or an `fn::rotate::external` adapter. Set a short expiry on the PAT
  when you create it.
- A DigitalOcean PAT is **account-wide**. For per-team scoping you still need
  RBAC inside the cluster, or DOKS SSO.
- `doctl` must be on `PATH` wherever the exec plugin runs, CI images included.
- Use `pulumi env run`, not `pulumi env open`, in anything that logs. `open`
  prints resolved secrets to stdout.

## References

- [ESC `files` reserved property](https://www.pulumi.com/docs/esc/environments/syntax/reserved-properties/files/)
- [ESC Kubernetes cluster access](https://www.pulumi.com/docs/esc/integrations/kubernetes/kubernetes/)
- [ESC providers](https://www.pulumi.com/docs/esc/providers/)
- [ESC rotators](https://www.pulumi.com/docs/esc/concepts/rotators/)
- [`doctl` kubeconfig expiry discussion](https://github.com/digitalocean/doctl/issues/791)
- [Stale kubeconfig in DO provider state](https://github.com/pulumi/pulumi-digitalocean/issues/312)

## License

MIT
