import * as pulumi from "@pulumi/pulumi";
import * as digitalocean from "@pulumi/digitalocean";

const config = new pulumi.Config();
const region = config.get("region") ?? "fra1";
const nodeSize = config.get("nodeSize") ?? "s-1vcpu-2gb";

const versions = digitalocean.getKubernetesVersions({});

const cluster = new digitalocean.KubernetesCluster("esc-demo", {
    region,
    version: versions.then((v) => v.latestVersion),
    // Deliberately cheap: one small node, no HA control plane, no autoscaling.
    nodePool: {
        name: "default",
        size: nodeSize,
        nodeCount: 1,
    },
    // Makes `pulumi destroy` also clean up load balancers / volumes the
    // cluster created for itself, so teardown does not leak billable resources.
    destroyAllAssociatedResources: true,
});

// Export ONLY the stable fields.
//
// Deliberately NOT exported: cluster.kubeConfigs[0].rawConfig.
// That blob embeds a DigitalOcean token with a 7 day default lifetime, so it
// goes stale inside Pulumi state and every consumer of the output inherits an
// expiring credential. See pulumi/pulumi-digitalocean#312.
//
// Endpoint, CA and id are stable for the life of the cluster, so ESC can read
// them once and mint the volatile part (the token) per kubectl invocation.
export const clusterId = cluster.id;
export const clusterName = cluster.name;
export const clusterEndpoint = cluster.endpoint;
export const clusterCaCertificate = cluster.kubeConfigs[0].clusterCaCertificate;
