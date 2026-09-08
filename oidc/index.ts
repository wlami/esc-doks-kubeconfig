import * as pulumi from "@pulumi/pulumi";
import * as service from "@pulumi/pulumiservice";

const config = new pulumi.Config();

// The Pulumi organization that will trust GitHub Actions.
const org = config.require("org");

// The subject claim your workflow presents. Read it from the workflow log
// rather than constructing it: GitHub emits one of two shapes, and the policy
// must match the one your repository actually sends.
//
//   repo:<owner>/<repo>:*                      name-based
//   repo:<owner>@<ownerId>/<repo>@<repoId>:*   immutable, with numeric IDs
const subject = config.require("subject");

// Registering an issuer alone grants nothing: Pulumi Cloud attaches a default
// policy that DENIES every exchange. The allow policy below opens the door, and
// its `sub` rule is the security boundary. Scope it to one repository; a loose
// pattern lets any GitHub repo mint tokens for this organization.
//
// NOTE: an org can hold only ONE issuer per URL. If someone already registered
// https://token.actions.githubusercontent.com in your org, this resource fails
// with "already registered" and you want scripts/05-add-oidc-policy.sh instead.
const issuer = new service.OidcIssuer("github-actions", {
    organization: org,
    name: "github-actions",
    url: "https://token.actions.githubusercontent.com",
    maxExpirationSeconds: 3600,
    policies: [{
        decision: service.AuthPolicyDecision.Allow,
        tokenType: service.AuthPolicyTokenType.Organization,
        authorizedPermissions: [service.AuthPolicyPermissionLevel.Standard],
        rules: {
            aud: `urn:pulumi:org:${org}`,
            sub: subject,
        },
    }],
});

export const issuerName = issuer.name;
export const trustedSubject = subject;
export const audience = `urn:pulumi:org:${org}`;
