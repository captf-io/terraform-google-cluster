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

# Pod CIDRs to nodes, for CNIs that route pod addresses natively instead of
# encapsulating them (Cluster.spec.clusterNetwork.pods). One rule per address
# family: a firewall rule cannot mix IPv4 and IPv6 source ranges.
resource "google_compute_firewall" "pod_ingress_firewalls" {
  for_each = local.pod_cidrs_by_family

  description             = "${local.description}: pods to nodes (${each.key})"
  direction               = "INGRESS"
  name                    = "${local.name_prefix}-pod-ingress-${each.key}"
  network                 = local.network_self_link
  priority                = 1000
  project                 = local.network_project
  source_ranges           = each.value
  target_service_accounts = distinct(local.node_service_accounts)

  allow {
    protocol = "all"
  }
}
