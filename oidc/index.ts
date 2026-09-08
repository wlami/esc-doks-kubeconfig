import * as pulumi from "@pulumi/pulumi";
import * as service from "@pulumi/pulumiservice";

const config = new pulumi.Config();

// The Pulumi organization that will trust GitHub Actions.
const org = config.require("org");
// The single GitHub repository allowed to mint tokens, as "owner/name".
const repo = config.require("repo");

// Registering an issuer alone grants nothing: Pulumi Cloud attaches a default
// policy that DENIES every exchange. The allow policy below is what actually
// opens the door, and its `sub` rule is the security boundary.
//
// `repo:<owner>/<name>:*` scopes minting to one repository across its refs.
// A looser pattern would let any GitHub repository obtain a token for this
// organization, which is the classic OIDC misconfiguration.
const issuer = new service.OidcIssuer("github-actions", {
    organization: org,
    name: "github-actions",
    url: "https://token.actions.githubusercontent.com",

    // Cap how long an exchanged Pulumi token stays valid. The workflow needs
    // seconds; an hour is already generous.
    maxExpirationSeconds: 3600,

    policies: [{
        decision: service.AuthPolicyDecision.Allow,
        tokenType: service.AuthPolicyTokenType.Organization,
        authorizedPermissions: [service.AuthPolicyPermissionLevel.Standard],
        rules: {
            aud: `urn:pulumi:org:${org}`,
            sub: `repo:${repo}:*`,
        },
    }],
});

export const issuerName = issuer.name;
export const trustedSubject = `repo:${repo}:*`;
export const audience = `urn:pulumi:org:${org}`;
