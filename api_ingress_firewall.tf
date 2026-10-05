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

# API ports on control-plane nodes from the load balancer and Google's health
# checkers. A proxy hides the client address, so the client allowlist is the
# Cloud Armor policy, not this rule (DESIGN.md decision 1).
resource "google_compute_firewall" "api_ingress_firewall" {
  count = local.module_endpoint ? 1 : 0

  description             = "${local.description}: API load balancer to control plane"
  direction               = "INGRESS"
  name                    = "${local.name_prefix}-api-ingress"
  network                 = local.network_self_link
  priority                = 1000
  project                 = local.network_project
  source_ranges           = sort(concat(local.google_probe_ranges, local.proxy_subnet_cidrs))
  target_service_accounts = [local.control_plane_service_account]

  allow {
    ports    = local.api_backend_ports
    protocol = "tcp"
  }
}
