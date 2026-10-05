# Design: terraform-google-cluster

Why this module looks the way it does. Each decision names the evidence it
rests on; anything not yet checked against a real project is listed under
"Unverified" and must be confirmed on the first reviewed apply.

Pins: `hashicorp/google` 8.5.0. Runtimes: Terraform >= 1.5, OpenTofu >= 1.6.
Conventions: [CONVENTIONS.md](CONVENTIONS.md). Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/>.

Provider facts below were read from the provider at the pin: the schema
(`hack/tf-run.sh schema`) for attribute names and types, and the source at
`v8.5.0` (`google/services/compute/*.go`) for ForceNew, defaults, diff
suppression and API calls.

The CAPTF Google Cloud modules are three repositories, one for each role:
[terraform-google-cluster](https://github.com/captf-io/terraform-google-cluster),
[terraform-google-machine](https://github.com/captf-io/terraform-google-machine) and
[terraform-google-machinepool](https://github.com/captf-io/terraform-google-machinepool). This file covers the `cluster` role and
the decisions shared with the others. Decision and Unverified numbers are the
same in all three repositories, so "decision 4" means the same everywhere; a
decision that concerns another role is a one-line pointer under its number.

## Scope

- One role here, `cluster`. The other roles are the other two repositories ([machine](https://github.com/captf-io/terraform-google-machine), [machinepool](https://github.com/captf-io/terraform-google-machinepool)).
- Bring-your-own network: the VPC, subnetwork, proxy-only subnet and Cloud
  NAT exist before the cluster. The cluster role creates firewall rules, the
  API load balancer and node service accounts.
- The API load balancer is internal by default; external is opt-in with an
  explicit allowed-CIDR list.
- Node service accounts are created by default; variables take existing
  ones.

## Decisions

### 1. API load balancer: proxy, not passthrough

The internal passthrough Network Load Balancer cannot hairpin: a backend's
packets to the forwarding-rule IP are routed back to the same VM by a local
route the guest agent installs (GCP internal passthrough NLB docs). A
joining control-plane node would then reach its own, not yet running,
apiserver and the join fails. The contract requires control-plane nodes to
reach the endpoint themselves.

So:

- Internal (default): regional internal proxy Network Load Balancer
  (`load_balancing_scheme = "INTERNAL_MANAGED"`,
  `google_compute_region_target_tcp_proxy`). The proxy opens a new
  connection to any healthy backend, so hairpin works. Requires a
  proxy-only subnet (`purpose = REGIONAL_MANAGED_PROXY`) in the VPC and
  region ("You must create a proxy-only subnet in each region of a VPC
  network where you use an Envoy-based internal proxy Network Load
  Balancer", internal proxy NLB overview). The cluster lists the region's
  subnetworks with the AIP-160 filter `purpose = "REGIONAL_MANAGED_PROXY"`
  (the Compute list API's documented `filter` syntax) and matches the
  network itself, because the data source returns no `purpose` and its
  `network_self_link` holds only the network's name (`filepath.Base` in
  `data_source_google_compute_subnetworks.go`). A postcondition fails the
  plan with the `gcloud` command that creates the subnet.
- External (opt-in): global external proxy Network Load Balancer
  (`EXTERNAL_MANAGED`) with a Cloud Armor security policy that allows only
  `allowed_cidrs` (VPC firewalls cannot filter clients behind a proxy).
  Cloud Armor backend security policies support the global external proxy
  NLB (Cloud Armor security policy overview). Its forwarding rules take
  "exactly one port from 1-65535" (external proxy NLB overview), so 6443
  and 9345 work. A basic match condition takes at most 10 ranges, so the
  allowlist is chunked into rules of 10. Nodes reach the endpoint through
  Cloud NAT, so the NAT egress IPs must be in `allowed_cidrs`; the README
  says so.
- The internal address uses `purpose = "SHARED_LOADBALANCER_VIP"` from the
  start (`purpose` is ForceNew), so the API and RKE2 supervisor forwarding
  rules share one IP: "The same regional internal IP address with purpose
  SHARED_LOADBALANCER_VIP can be used by forwarding rules for ... Regional
  internal proxy Network Load Balancers" (forwarding rule concepts). Global
  forwarding rules share a global address on different ports.
- The address is a resource of its own, so a forwarding rule replacement
  (its `ip_address`, `port_range` and `description` are ForceNew) keeps the
  endpoint.
- Backend services: TCP, `timeout_sec = 3600`. For proxy NLBs the backend
  service timeout is an idle timeout, 30 s by default, configurable from 1
  to 2,147,483,647 s (backend services overview); 30 s cuts idle watches and
  `kubectl logs -f`. `UTILIZATION` balancing with `capacity_scaler = 1` and
  `max_utilization = 0.8` written out: the provider requires
  `capacity_scaler` for non-INTERNAL backend services and defaults the rest,
  so explicit values cannot drift. TCP health checks every 5 s, one backend
  per zone.
- Firewall sources: Google's probes come from `35.191.0.0/16` and
  `130.211.0.0/22` (health check concepts); the external load balancer's
  proxied connections come from the same ranges (external proxy NLB
  overview); the internal one's from the proxy-only subnet.
  `34.96.0.0/20` and `34.127.192.0/18` are the ranges Google's front ends use
  towards external (internet NEG) backends, not instance group backends, so
  they are not allowed.
- Pod CIDRs: one firewall rule per address family, since a rule cannot mix
  IPv4 and IPv6 source ranges.
- Checks on what data sources read are preconditions on resources, not data
  postconditions: data sources are read during destroy too, and a check
  there (a proxy-only subnet removed after the load balancer) would block
  the cluster's destroy.
- Backends are per-zone unmanaged instance groups the cluster creates
  (`ignore_changes = [instances]`; `instances` is optional and computed);
  control-plane machines join them with
  `google_compute_instance_group_membership` in their own state. Instance
  group names are zonal, so every zone uses `<prefix>-control-plane`.
- Listeners are keyed `kube_apiserver` and `rke2_supervisor`
  (`distribution = "rke2"`), as in every CAPTF module; resource names use
  `apiserver` and `supervisor` to stay within 63 characters. The endpoint's
  port is `cluster_network.api_server_port`; the kube-apiserver backend port
  is the same with kubeadm and always 6443 with RKE2, which never reads
  `apiServerPort` (control-planes/rke2.md). With RKE2, an API port of 9345
  fails a precondition.
- `terraform_data.api_endpoint_guard` records `api_load_balancer_public`,
  the network, subnetwork, project, region, API port and the address when
  the load balancer is created (`ignore_changes = [input]`), and a
  postcondition fails any later plan that changes them (CONVENTIONS.md
  section 12): CAPI never updates the endpoint, and the controller's
  destructive-plan guard misses in-place changes and can be approved. The
  address has its own postcondition: it is unknown while its replacement is
  planned, which would defer a combined check to apply time.
- The node subnetwork is read through a listing filtered by name, and the
  network's self link is built from its name: a singular read fails once
  the brought network is gone, and data sources are read during destroy
  (CONVENTIONS.md section 9).
- No `prevent_destroy` and no `deletion_policy = "PREVENT"`: both block
  cluster deletion. The destructive-plan guard catches replacement.

### 2. Firewall rules target service accounts

Rules use `target_service_accounts`/`source_service_accounts`, not network
tags, so a rule cannot be satisfied by an instance that merely sets a tag.
Rules: intra-cluster (all protocols between the node service accounts);
pod CIDRs to nodes when `cluster_network.pods` is set; API ports from the
proxy-only subnet (internal) and Google's proxy and health-check ranges
`35.191.0.0/16` and `130.211.0.0/22`. Instances still carry a node network
tag because cloud-provider-gcp needs one for Service firewall rules. Shared
VPC: rules live in the host project (`network_project`).

trivy reads a rule without `source_ranges` as open to `0.0.0.0/0`; the
intra-cluster rule's findings are ignored in `.trivyignore.yaml` with that
reason.

### 3. Node identities

Two service accounts (control plane, workers) with predefined roles only:
control plane `compute.viewer`, `compute.loadBalancerAdmin`,
`compute.securityAdmin`, `compute.storageAdmin`, `compute.instanceAdmin.v1`,
`logging.logWriter`, `monitoring.metricWriter`; workers `logging.logWriter`,
`monitoring.metricWriter`. The control-plane account gets
`iam.serviceAccountUser` on each node account (scoped to that account) so
the PD CSI driver can attach disks. No custom roles: a deleted custom role
ID cannot be reused for 7 to 37 days, which breaks recreating a cluster of
the same name. Users can override the role lists or bring their own
accounts.

A user-managed service account's email is
`<account_id>@<project>.iam.gserviceaccount.com`, so the module derives it
from the resource's configured `account_id` and `project` instead of reading
the computed `email`: firewall rules and IAM bindings plan with real values,
and the mocked tests produce valid IAM members. When a refresh no longer finds a
module-created account, the same address is built from configuration alone,
so `apply -refresh-only` does not fail on an empty `coalesce`.

### 4. Machine

Concerns the machine role: see [terraform-google-machine DESIGN.md](https://github.com/captf-io/terraform-google-machine/blob/main/DESIGN.md#4-machine).

### 5. Machine pool

Concerns the machinepool role: see [terraform-google-machinepool DESIGN.md](https://github.com/captf-io/terraform-google-machinepool/blob/main/DESIGN.md#5-machine-pool).

### 6. provider_id, addresses, health

A vanished API forwarding rule makes the cluster terminated
(`LoadBalancerNotFound`). The rest concerns the machine and machinepool roles: see
[terraform-google-machine DESIGN.md](https://github.com/captf-io/terraform-google-machine/blob/main/DESIGN.md#6-provider_id-addresses-health).

### 7. Labels

GCP label keys match `[a-z][a-z0-9_-]{0,62}` and values `[a-z0-9_-]{0,63}`:
no `.` or `/`. Mapping: lowercase, `.` to `-`, other invalid characters to
`_` (`captf.io/cluster` → `captf-io_cluster`); values lowercased, invalid
characters to `_`, longer than 63 characters cut to 54 plus `-` plus 8 hex
characters of the original's sha256. An empty `captf.io/template` stays
empty.

Labels are set explicitly on every labelable resource and on nested
labels (boot disk, `all_instances_config.labels`), never through provider
`default_labels`; `add_terraform_attribution_label = false`, so the labels
on a resource are exactly the documented ones. Not labelable in 8.5.0:
firewall rules, backend services, health checks, target proxies, unmanaged
instance groups, managed instance groups, autoscalers, service accounts and
IAM members.

Their descriptions name the owning object (`CAPTF cluster <ns>/<name>`),
never `captf_tags`: `description` is ForceNew on addresses, forwarding
rules, target proxies, instance groups and managed instance groups, and
`captf.io/template` changes on a ClusterClass rebase. The earlier design's
`jsonencode(var.captf_tags)` descriptions would have replaced them, the
API address included.

### 8. Credentials

Identity Secret: `GOOGLE_CREDENTIALS` (service account key JSON or an
`external_account` JSON), `GOOGLE_PROJECT`, `GOOGLE_REGION`; or a
`credentials.json` file key with
`GOOGLE_APPLICATION_CREDENTIALS=/var/run/captf/credentials/credentials.json`.
The provider block sets `project` and `region` from variables (cluster) or
exports (machine, pool); null falls back to the environment. The cluster
reads the effective values with `data.google_client_config` and fails a
postcondition when either is empty.

## Exports

Schema `captf.io/gcp-cluster/v1`:

```hcl
{
  schema           = "captf.io/gcp-cluster/v1"
  project          = "<project>"
  region           = "<region>"
  network          = "<self link>"
  subnetwork       = "<self link>"
  name_prefix      = "<prefix>"
  failure_domains  = { "<zone>" = { zone = "<zone>" } }
  node_network_tag = "<prefix>-node"
  control_plane    = { service_account = "<email>", network_tags = [...] }
  worker           = { service_account = "<email>", network_tags = [...] }
  api              = { host = "<ip>", port = <api_server_port>, backend_port = <6443 with RKE2, else api_server_port>, instance_groups = { "<zone>" = "<self link>" } } # null for a user endpoint
}
```

The failure domains' attributes carry the zone (the earlier design had
`{}`), the same map the cluster's `failure_domains` output carries as
`attributes`. Registration targets are per-zone instance groups, shared by
both listeners, rather than one target per listener keyed `kube_apiserver`
and `rke2_supervisor` (CONVENTIONS.md section 12): a GCP backend is an
instance group, and one group serves every backend service.

## Unverified

**1.** The proxy-only subnet filter `purpose = "REGIONAL_MANAGED_PROXY"` on a
real project (the syntax is the Compute API's documented AIP-160 form).

**2.** Minimal role set for cloud-provider-gcp and PD CSI, and the identity's
role set listed in the cluster README.

**8.** Firewall rules naming a service account created moments earlier in the
same apply (IAM eventual consistency).

Verified since the first draft: the external proxy NLB accepts any port.

Items 3-7 and 9-11 concern the machine and machinepool roles; see their DESIGN.md.

## Rejected alternatives

- Internal passthrough NLB (no hairpin).
- Custom IAM roles (ID reuse block).
- Provider `default_labels` (misses nested labels; untestable).
- `captf_tags` in descriptions (ForceNew; would replace the API address).
