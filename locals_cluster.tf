# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Cluster-wide values every resource shares: where the cluster lives, which
# API load balancer it gets, and which node identities it uses (DESIGN.md
# decisions 1 to 3).
locals {
  # The provider's effective project and region: the variables when set,
  # else GOOGLE_PROJECT and GOOGLE_REGION from the identity Secret.
  project         = data.google_client_config.provider_config.project
  region          = data.google_client_config.provider_config.region
  network_project = coalesce(var.network_project, local.project)

  # The relative path a subnetwork's "network" URL ends in, whatever its API
  # version prefix.
  network_path      = "projects/${local.network_project}/global/networks/${var.network}"
  network_self_link = "https://www.googleapis.com/compute/v1/${local.network_path}"
  # The brought subnetwork, or null once it is gone (the precondition on
  # node_internal_firewall.tf requires it on every plan but a destroy).
  node_subnetwork      = one([for s in data.google_compute_subnetworks.node_subnetworks.subnetworks : s if s.name == var.subnetwork])
  node_subnetwork_ok   = local.node_subnetwork != null && endswith(coalesce(try(local.node_subnetwork.network, null), "-"), "/${local.network_path}")
  subnetwork_self_link = try(local.node_subnetwork.self_link, "https://www.googleapis.com/compute/v1/projects/${local.network_project}/regions/${local.region}/subnetworks/${var.subnetwork}")

  # Failure domains are zones: subnetworks are regional in GCP.
  zones = length(var.zones) > 0 ? sort(var.zones) : sort(data.google_compute_zones.region_zones.names)

  # The endpoint's port is cluster_network.api_server_port (default 6443).
  # The kube-apiserver backend port is the same with kubeadm, by contract
  # convention equal to its bindPort (cluster.md "cluster_network"), and
  # always 6443 with RKE2, which never reads apiServerPort
  # (control-planes/rke2.md).
  api_port         = coalesce(try(var.cluster_network.api_server_port, null), 6443)
  api_backend_port = var.distribution == "rke2" ? 6443 : local.api_port
  pod_cidrs        = try(coalesce(var.cluster_network.pods, []), [])
  # Dual-stack clusters list both families; only non-empty ones get a rule.
  pod_cidrs_by_family = {
    for family, cidrs in {
      v4 = [for c in local.pod_cidrs : c if !strcontains(c, ":")]
      v6 = [for c in local.pod_cidrs : c if strcontains(c, ":")]
    } : family => cidrs if length(cidrs) > 0
  }

  # A non-null control_plane_endpoint input means the endpoint is not ours:
  # no load balancer, no API firewall rule, nothing for machines to join.
  module_endpoint = var.control_plane_endpoint == null
  internal_lb     = local.module_endpoint && !var.api_load_balancer_public
  external_lb     = local.module_endpoint && var.api_load_balancer_public

  # One listener per port, keyed as in every CAPTF module. RKE2 joins at
  # https://<endpoint host>:9345, so the supervisor shares the API address
  # (control-planes/rke2.md). name keeps resource names within 63 characters.
  api_listeners = merge(
    {
      kube_apiserver = { frontend_port = local.api_port, backend_port = local.api_backend_port, port_name = "apiserver", name = "apiserver" }
    },
    var.distribution == "rke2" ? {
      rke2_supervisor = { frontend_port = 9345, backend_port = 9345, port_name = "rke2-supervisor", name = "supervisor" }
    } : {},
  )
  api_backend_ports = sort(distinct([for l in local.api_listeners : tostring(l.backend_port)]))

  # Google's front ends and health checkers: proxied client connections of
  # the external load balancer and every health check probe
  # (https://cloud.google.com/load-balancing/docs/health-check-concepts).
  google_probe_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  # The internal proxy load balancer connects to backends from the
  # proxy-only subnet (or subnets, while one drains).
  proxy_subnet_cidrs = sort([
    for s in try(data.google_compute_subnetworks.proxy_subnetworks[0].subnetworks, []) :
    s.ip_cidr_range if endswith(s.network, "/${local.network_path}")
  ])

  # Node identities: module-created unless the user brings their own.
  created_service_accounts = {
    for role, id in local.service_account_ids : role => id
    if(role == "control-plane" ? var.control_plane_service_account : var.worker_service_account) == null
  }
  # A user-managed service account's email is <account_id>@<project>.iam.gserviceaccount.com
  # (https://cloud.google.com/iam/docs/service-account-overview), known at plan
  # time, so firewall rules and bindings plan with real values.
  created_service_account_emails = {
    for role, a in google_service_account.node_service_accounts : role => "${a.account_id}@${a.project}.iam.gserviceaccount.com"
  }
  # The fallback is the same address from configuration alone: a refresh
  # after an out-of-band delete drops the account from the map above.
  control_plane_service_account = coalesce(var.control_plane_service_account, lookup(local.created_service_account_emails, "control-plane", "${local.service_account_ids["control-plane"]}@${local.project}.iam.gserviceaccount.com"))
  worker_service_account        = coalesce(var.worker_service_account, lookup(local.created_service_account_emails, "worker", "${local.service_account_ids["worker"]}@${local.project}.iam.gserviceaccount.com"))
  node_service_accounts         = [local.control_plane_service_account, local.worker_service_account]
}
