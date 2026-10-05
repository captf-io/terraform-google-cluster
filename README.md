# terraform-google-cluster

The CAPTF Google Cloud cluster module: the Terraform/OpenTofu root module
behind `TerraformCluster`. This repository holds the code; the module images
are published from [captf-io/gcp-modules](https://github.com/captf-io/gcp-modules)
as `ghcr.io/captf-io/gcp-cluster`.

The `cluster` role of the CAPTF modules for Google Cloud: the API load
balancer, the firewall rules and the node identities of one Cluster API
cluster, in a network you bring. Image: `ghcr.io/captf-io/gcp-cluster`. Used
by a `TerraformCluster`; contract:
<https://captf.io/docs/module-author/contract/v1alpha1/cluster.html>.

## Usage

CAPTF runs this module from the module image `ghcr.io/captf-io/gcp-cluster`: set the image on
a `TerraformCluster`'s `spec.source.image`, and the controller renders every
input. The module is also published to the Terraform Registry as
`captf-io/cluster/google` and can be called directly:

```hcl
module "cluster" {
  source  = "captf-io/cluster/google"
  version = "~> 0.1"

  # The contract inputs the controller would render (captf_contract,
  # captf_cluster, captf_object, captf_tags, ...; see Inputs), and any
  # user variables.
}
```

Called directly, the module is a CAPTF root module first:

- it configures its own `provider "google"` block, so the calling
  module cannot use `count`, `for_each` or `depends_on` on it, and the
  provider takes its credentials from the environment (see Identity
  Secret);
- its providers are pinned to exact versions (`versions.tf`), which the
  calling configuration has to accept;
- you set the `captf_*` inputs yourself.

## What it creates

| Resource | Type | When |
| --- | --- | --- |
| `node_service_accounts` | `google_service_account` | One per node role (`control-plane`, `worker`) unless `control_plane_service_account` or `worker_service_account` brings one |
| `node_project_roles` | `google_project_iam_member` | `control_plane_roles` and `worker_roles` for the accounts the module created |
| `node_service_account_users` | `google_service_account_iam_member` | `roles/iam.serviceAccountUser` for the control-plane account on each account the module created, so the PD CSI controller can attach disks |
| `node_internal_firewall` | `google_compute_firewall` | Always: every protocol between the node service accounts |
| `api_endpoint_guard` | `terraform_data` | Without a user endpoint: records what decides the endpoint and fails a plan that would change it |
| `pod_ingress_firewalls` | `google_compute_firewall` | When `Cluster.spec.clusterNetwork.pods` is set: the pod CIDRs to the nodes, one rule per address family (`v4`, `v6`) |
| `api_ingress_firewall` | `google_compute_firewall` | Without a user endpoint: the API ports on control-plane nodes from the load balancer and Google's health checkers |
| `api_instance_groups` | `google_compute_instance_group` | Without a user endpoint: one unmanaged instance group per zone, the API backends that control-plane machines join |
| `api_address` | `google_compute_address` | Internal endpoint (default): the API address, `SHARED_LOADBALANCER_VIP` |
| `api_region_health_checks` | `google_compute_region_health_check` | Internal endpoint: one TCP check per listener |
| `api_region_backend_services` | `google_compute_region_backend_service` | Internal endpoint: one per listener, `INTERNAL_MANAGED` |
| `api_region_target_tcp_proxies` | `google_compute_region_target_tcp_proxy` | Internal endpoint: one per listener |
| `api_forwarding_rules` | `google_compute_forwarding_rule` | Internal endpoint: one per listener, on the API address |
| `api_global_address` | `google_compute_global_address` | `api_load_balancer_public`: the public API address |
| `api_security_policy` | `google_compute_security_policy` | `api_load_balancer_public`: Cloud Armor allowlist of `api_allowed_cidrs` |
| `api_health_checks` | `google_compute_health_check` | `api_load_balancer_public`: one TCP check per listener |
| `api_backend_services` | `google_compute_backend_service` | `api_load_balancer_public`: one per listener, `EXTERNAL_MANAGED` |
| `api_target_tcp_proxies` | `google_compute_target_tcp_proxy` | `api_load_balancer_public`: one per listener |
| `api_global_forwarding_rules` | `google_compute_global_forwarding_rule` | `api_load_balancer_public`: one per listener, on the public address |

The listeners are `kube_apiserver` (frontend `cluster_network.api_server_port`,
6443 by default; backend the same with kubeadm, always 6443 with RKE2) and,
with `distribution = "rke2"`, `rke2_supervisor` (9345). Data sources
read the provider's project and region, the node subnetwork and the
proxy-only subnet (listings, which return nothing rather than fail once a
brought subnetwork is gone, so a destroy is never blocked) and the region's
zones. The network is not read: its self link is built from its name and
`network_project`.

Why a proxy load balancer: a control-plane node must reach the endpoint it
is itself behind (`cluster.md` "Hairpin reachability"). An internal
passthrough load balancer routes a backend's packets to the forwarding
rule's address back to the backend itself, so a joining node would reach
its own, not yet running, API server. A proxy opens a new connection to a
healthy backend. See [DESIGN.md](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md) decision 1.

## Prerequisites

- **Network** (bring your own): a VPC network, a regional subnetwork for the
  nodes, Cloud NAT (nodes have no external IP and need egress for images and
  packages), and, for the default internal endpoint, a proxy-only subnet in
  the same network and region:

  ```sh
  gcloud compute networks subnets create captf-proxy-only \
    --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE \
    --network=<network> --region=<region> --range=<an unused /23>
  ```

  One proxy-only subnet serves every Envoy-based load balancer of the network
  in that region. The plan fails with this command in its message when it is
  missing.
- **Reachability of the internal endpoint**: the management cluster must
  reach the API address in `subnetwork`: from the same VPC, a peered network,
  a VPN or Interconnect. Clients outside the cluster's region need
  `api_global_access`.
- **Shared VPC**: set `network_project` to the host project. The firewall
  rules are created there, the rest in `project`. cloud-provider-gcp then
  needs `network-project-id = <host project>` in `gce.conf`, and the
  control-plane service account needs `roles/compute.loadBalancerAdmin` and
  `roles/compute.securityAdmin` in the host project too: the module binds
  `control_plane_roles` in `project` only.
- **Address ranges**: the Pod and Service CIDRs must not overlap the VPC's
  subnetworks or the proxy-only subnet. An auto-mode network uses
  10.128.0.0/9.
- **Quotas**: one internal or global address, one or two forwarding rules,
  backend services, target proxies and health checks, one instance group per
  zone, three or four firewall rules, two service accounts.
- **Permissions of the identity**, for all three roles. This set is expected
  to suffice; it has not yet been checked against a real project (DESIGN.md
  "Unverified").

  | Role | Granted on | For |
  | --- | --- | --- |
  | `roles/compute.loadBalancerAdmin` | `project` | Addresses, forwarding rules, backend services, health checks, target proxies (cluster) |
  | `roles/compute.instanceAdmin.v1` | `project` | Instance groups (cluster), instances and memberships (machine), templates, groups, autoscalers (machinepool) |
  | `roles/compute.securityAdmin` | `project` and `network_project` | Firewall rules, Cloud Armor policy (cluster) |
  | `roles/compute.networkViewer` | `network_project` | Reading the network and subnetworks (cluster) |
  | `roles/compute.networkUser` | the node subnetwork, Shared VPC only | Instances in the host project's subnetwork (machine, machinepool) |
  | `roles/iam.serviceAccountAdmin` | `project` | Creating the node accounts and granting actAs on them (cluster; not needed when you bring both) |
  | `roles/resourcemanager.projectIamAdmin` | `project` | Binding `control_plane_roles` and `worker_roles` (cluster; not needed when you bring both) |
  | `roles/iam.serviceAccountUser` | the two node service accounts only, never the project | Running instances as them (machine, machinepool) |
  | `roles/secretmanager.admin` | `project` | Staged control-plane bootstrap secrets and their access bindings (machine) |

## Inputs

Contract inputs used: `captf_cluster` (names), `captf_tags` (labels),
`control_plane_endpoint` (a non-null value skips the load balancer),
`cluster_network` (`pods` for the pod firewall rule, `api_server_port` for the
API port). `captf_contract` is validated. `captf_object`,
`kubernetes_version`, `control_plane_initialized` and `captf_cluster_outputs`
are declared and unused.

User variables (`TerraformCluster.spec.variables`):

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `additional_tags` | `map(string)` | `{}` | Extra GCP labels for every labelable resource. Keys and values must already be valid GCP labels; the captf-io_ keys are reserved for captf_tags, which win. |
| `api_allowed_cidrs` | `list(string)` | `[]` | Client CIDRs allowed to reach the public API endpoint, enforced by a Cloud Armor policy. Required when api_load_balancer_public is true; include the Cloud NAT egress addresses so nodes can reach the endpoint. |
| `api_global_access` | `bool` | `false` | Let clients in any region of the VPC reach the internal API endpoint. Off by default: only clients in the cluster's region can. |
| `api_load_balancer_public` | `bool` | `false` | Serve the API through a global external proxy load balancer instead of the internal one. Off by default; requires api_allowed_cidrs. |
| `control_plane_roles` | `list(string)` | `["roles/compute.instanceAdmin.v1", "roles/compute.loadBalancerAdmin", "roles/compute.securityAdmin", "roles/compute.storageAdmin", "roles/compute.viewer", "roles/logging.logWriter", "roles/monitoring.metricWriter"]` | Project roles for a module-created control-plane service account: what cloud-provider-gcp and the PD CSI controller need. Ignored with control_plane_service_account. |
| `control_plane_service_account` | `string` | `null` | Email of an existing service account for control-plane nodes. Null creates one with control_plane_roles. |
| `distribution` | `string` | `"kubeadm"` | Kubernetes distribution of the control plane: kubeadm, or rke2, which adds the RKE2 supervisor port 9345 on the API address and always uses kube-apiserver port 6443 on the nodes. kubeadm by default. |
| `network` | `string` | `null` | Name of the existing VPC network the cluster runs in (bring your own network). Required. |
| `network_project` | `string` | `null` | Project that owns the network: the host project of a Shared VPC. Null means the cluster's own project. Firewall rules are created here. |
| `project` | `string` | `null` | Project to create the cluster in. Null uses the provider's project: GOOGLE_PROJECT from the identity Secret, or the credentials' project. |
| `region` | `string` | `null` | Region of the cluster. Null uses the provider's region: GOOGLE_REGION from the identity Secret. |
| `subnetwork` | `string` | `null` | Name of the existing regional subnetwork, in network, that nodes and the internal API address use. Required. |
| `worker_roles` | `list(string)` | `["roles/logging.logWriter", "roles/monitoring.metricWriter"]` | Project roles for a module-created worker service account: logs and metrics only. Ignored with worker_service_account. |
| `worker_service_account` | `string` | `null` | Email of an existing service account for worker nodes. Null creates one with worker_roles. |
| `zones` | `list(string)` | `[]` | Zones of the region to use as failure domains. Empty means every zone of the region; set it when the machine type is not offered everywhere. |

## Outputs

| Name | Value |
| --- | --- |
| `control_plane_endpoint` | The user's endpoint when given; else `{host = <API address>, port = <API port>}`. The address is its own resource, so the endpoint survives a forwarding rule replacement. |
| `failure_domains` | One per zone: `{name = <zone>, control_plane = true, attributes = {zone = <zone>}}`. |
| `exports` | Below. |
| `health` | Below. |

Non-contract outputs (`outputs_extra.tf`): `api_address_id`,
`api_backend_service_ids`, `api_forwarding_rule_ids`, `api_instance_group_ids`,
`firewall_rule_ids`, `node_service_account_ids`, `proxy_subnet_cidrs`.

## Exports

Schema `captf.io/gcp-cluster/v1`, handed to every machine and pool as
`captf_cluster_outputs`. Nothing in it is secret.

| Key | Value |
| --- | --- |
| `schema` | `"captf.io/gcp-cluster/v1"` |
| `project`, `region` | Where machines and pools are created |
| `network`, `subnetwork` | Self links of the network and the node subnetwork |
| `name_prefix` | `captf-<namespace>-<cluster>` (truncated) plus 8 hex characters of the cluster key's sha256 |
| `failure_domains` | `{"<zone>" = {zone = "<zone>"}}` |
| `node_network_tag` | `<name_prefix>-node`, on every node; set it as `node-tags` in cloud-provider-gcp's `gce.conf` |
| `control_plane`, `worker` | `{service_account = <email>, network_tags = [<node tag>, <role tag>]}` |
| `api` | `{host, port, backend_port, instance_groups = {"<zone>" = <self link>}}`; `null` with a user endpoint |

A machine or pool of an externally managed TerraformCluster receives `{}`
and reads the same object from its `external_cluster_exports` variable.

## Identity Secret

The identity's Secret holds the Google provider's credentials; every key
becomes an environment variable of the Job and a file under
`/var/run/captf/credentials/`:

| Key | Value |
| --- | --- |
| `GOOGLE_CREDENTIALS` | A service account key JSON, or an `external_account` (workload identity federation) JSON |
| `GOOGLE_PROJECT` | Default project, when `project` is not set |
| `GOOGLE_REGION` | Default region, when `region` is not set |

Alternatively, a `credentials.json` key plus
`GOOGLE_APPLICATION_CREDENTIALS=/var/run/captf/credentials/credentials.json`.
See [examples/identity.yaml](https://github.com/captf-io/terraform-google-cluster/blob/main/examples/identity.yaml).

## Tags

Every labelable resource (the addresses, forwarding rules and the security
policy) carries `merge(additional_tags, captf_tags)` as GCP labels, captf
keys last. GCP label keys match `[a-z][a-z0-9_-]{0,62}` and values
`[a-z0-9_-]{0,63}`, so `captf_tags` are mapped:

- keys: lowercase, `.` to `-`, other invalid characters to `_`:
  `captf.io/cluster` becomes `captf-io_cluster`; injective over the
  contract's fixed keys;
- values: lowercase, invalid characters to `_`; longer than 63 characters,
  the first 54 plus `-` plus 8 hex characters of the original's sha256.

`additional_tags` must already be valid GCP labels and may not use the
`captf-io_` prefix; at most 58, since GCP allows 64 per resource.

Not labelable in `hashicorp/google` 8.5.0: firewall rules, instance groups,
health checks, backend services, target proxies, service accounts and IAM
members. They carry the cluster's name prefix, and their description names
the Cluster (`CAPTF cluster <namespace>/<name>`); never `captf_tags`,
because `description` is ForceNew on several of them and
`captf.io/template` can change.

## Health

From the cluster's own resource, the API forwarding rule (never from its
backends, which are unhealthy during every control-plane bring-up):

| Situation | `state` | `healthy` | `reasons` |
| --- | --- | --- | --- |
| User endpoint (no load balancer) | `running` | `true` | `[]` |
| The `kube_apiserver` forwarding rule exists | `running` | `true` | `[]` |
| A refresh no longer finds the forwarding rule | `terminated` | `false` | `["LoadBalancerNotFound"]` |

## Limitations

- The endpoint is fixed once the load balancer exists: CAPI never updates
  it. `api_endpoint_guard` records `api_load_balancer_public`, `network`,
  `subnetwork`, `project`, `region`, the API port and the address when the
  load balancer is created, and fails any later plan that would change one
  of them, in place or by replacement. Revert the change, or create a new
  cluster.
- Changing `zones` adds or removes instance groups; removing a zone that
  still has control-plane machines fails while they are members. Existing
  machine pools without their own failure domains keep the zones they were
  created with (a zone change would replace their groups); new pools use the
  new zones.
- With a brought worker account and a module-created control-plane
  account, grant the control-plane account `roles/iam.serviceAccountUser` on
  the worker account yourself: the module grants it only on accounts it
  created, and the PD CSI controller needs it to attach disks to workers.
- `api_load_balancer_public` uses Google's front ends: the nodes reach the endpoint
  through Cloud NAT, so `api_allowed_cidrs` must include the NAT's egress
  addresses (static ones).
- No firewall rule for SSH, and no external IPs: use IAP TCP forwarding or
  OS Login through a bastion of your own.
- `prevent_destroy` is not set on the address: it would block cluster
  deletion too. The destructive-plan guard catches a replacement.

## Exceptions

- `exports.api` carries per-zone `instance_groups` instead of one
  registration target per listener keyed `kube_apiserver` and
  `rke2_supervisor` (CONVENTIONS.md section 12): a Google Cloud backend is
  an instance group, and one group serves both listeners (DESIGN.md
  "Exports").

## Examples

[examples/cluster-kubeadm.yaml](https://github.com/captf-io/terraform-google-cluster/blob/main/examples/cluster-kubeadm.yaml) creates a
TerraformCluster with this image:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: TerraformCluster
metadata:
  name: demo
spec:
  source:
    image: ghcr.io/captf-io/gcp-cluster:v0.1.0-opentofu
  identityRef:
    name: gcp
  variables:
    network: captf-vpc
    subnetwork: captf-nodes
```

## Development

The host needs make, podman (or docker with `ENGINE=docker`), jq and Go.
Every other tool runs in a digest-pinned container. `make verify` is the
gate. `make help` lists the targets:

- `make fmt`: format the module with `terraform fmt` and `tofu fmt`, in place.
- `make fmt-check`: fail on any file the formatters would change.
- `make validate`: `init` and `validate` on both runtimes and on their floors
  (Terraform 1.5.7, OpenTofu 1.6.3).
- `make unit-test`: `terraform test` and `tofu test` with mocked providers.
- `make tflint`: tflint with the terraform ruleset (preset all) and the cloud
  ruleset.
- `make tfcapi-lint`: `tfcapi-lint module --strict`, built from `PROVIDER_DIR`
  (default `../cluster-api-provider-terraform`, a clone of
  [cluster-api-provider-terraform](https://github.com/captf-io/cluster-api-provider-terraform)
  next to this one); skipped when it is absent.
- `make scan`: trivy config over the repository; ignores live in
  `.trivyignore.yaml`.
- `make check-conventions`: the layout and tag checks (`hack/check-layout.sh`,
  `hack/check-tags.sh`) for CONVENTIONS.md.
- `make shellcheck`: shellcheck over `hack/` and every shell template.
- `make check-headers`, `make fix-headers`: check or add the Apache-2.0 license
  header.
- `make verify`: all of the above, in parallel groups.
- `make clean`: remove `build/`; keeps `.cache/` and `.tools/`.

Useful variables: `RUNTIMES=opentofu` (or `terraform`), `ENGINE=docker`,
`PROVIDER_DIR=<path>`.
