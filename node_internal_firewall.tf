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

# Every protocol between the cluster's nodes (etcd, kubelet, CNI, NodePorts),
# matched by service account, not network tag (DESIGN.md decision 2). The
# role's primary resource: it always exists, so it carries the cross-variable checks.
resource "google_compute_firewall" "node_internal_firewall" {
  # count = 1, not a single resource: a refresh after an out-of-band delete
  # reads an empty tuple instead of an unknown (CONVENTIONS.md section 9).
  count = 1

  description             = "${local.description}: node to node"
  direction               = "INGRESS"
  name                    = "${local.name_prefix}-node-internal"
  network                 = local.network_self_link
  priority                = 1000
  project                 = local.network_project
  source_service_accounts = distinct(local.node_service_accounts)
  target_service_accounts = distinct(local.node_service_accounts)

  allow {
    protocol = "all"
  }

  lifecycle {
    precondition {
      condition     = local.node_subnetwork_ok
      error_message = "subnetwork ${var.subnetwork} is not a subnetwork of network ${var.network} in region ${local.region}: set spec.variables.subnetwork to one that is."
    }
    precondition {
      condition     = length(setsubtract(var.zones, data.google_compute_zones.region_zones.names)) == 0
      error_message = "zones must be zones of region ${local.region}; these are not: ${join(", ", setsubtract(var.zones, data.google_compute_zones.region_zones.names))}."
    }
    precondition {
      condition     = length(local.zones) > 0
      error_message = "Region ${local.region} reports no zones: set spec.variables.zones."
    }
    precondition {
      condition     = !local.external_lb || length(var.api_allowed_cidrs) > 0
      error_message = "api_allowed_cidrs is required with api_load_balancer_public: set spec.variables.api_allowed_cidrs to the client CIDRs allowed to reach the API, including the Cloud NAT egress addresses of the nodes."
    }
    precondition {
      condition     = !(var.distribution == "rke2" && local.api_port == 9345)
      error_message = "cluster_network.api_server_port 9345 collides with the RKE2 supervisor port 9345: use another API port."
    }
  }
}
