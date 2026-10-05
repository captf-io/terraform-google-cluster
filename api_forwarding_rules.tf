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

# Forwarding rules of the internal proxy load balancer, one port each on the
# shared API address (https://cloud.google.com/load-balancing/docs/tcp/internal-proxy).
# Without a proxy-only subnet the precondition below fails the plan first.
resource "google_compute_forwarding_rule" "api_forwarding_rules" {
  for_each = local.internal_lb ? local.api_listeners : {}

  allow_global_access   = var.api_global_access
  description           = "${local.description}: ${each.value.port_name}"
  ip_address            = google_compute_address.api_address[0].address
  ip_protocol           = "TCP"
  labels                = local.tags
  load_balancing_scheme = "INTERNAL_MANAGED"
  name                  = "${local.name_prefix}-api-${each.value.name}"
  network               = local.network_self_link
  port_range            = tostring(each.value.frontend_port)
  project               = local.project
  region                = local.region
  subnetwork            = local.subnetwork_self_link
  target                = google_compute_region_target_tcp_proxy.api_region_target_tcp_proxies[each.key].id

  lifecycle {
    precondition {
      condition     = length(local.proxy_subnet_cidrs) > 0
      error_message = "No proxy-only subnet in network ${var.network}, region ${local.region}: the internal API load balancer needs one. Create it with `gcloud compute networks subnets create <name> --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE --network=${var.network} --region=${local.region} --range=<unused /23>`, migrate a legacy INTERNAL_HTTPS_LOAD_BALANCER proxy-only subnet to REGIONAL_MANAGED_PROXY, or set spec.variables.api_load_balancer_public."
    }
  }
}
