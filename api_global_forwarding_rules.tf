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

# Forwarding rules of the global external proxy load balancer, one port each
# (any of 1-65535) on the shared public address
# (https://cloud.google.com/load-balancing/docs/tcp).
resource "google_compute_global_forwarding_rule" "api_global_forwarding_rules" {
  for_each = local.external_lb ? local.api_listeners : {}

  description           = "${local.description}: ${each.value.port_name}"
  ip_address            = google_compute_global_address.api_global_address[0].address
  ip_protocol           = "TCP"
  labels                = local.tags
  load_balancing_scheme = "EXTERNAL_MANAGED"
  name                  = "${local.name_prefix}-api-${each.value.name}"
  port_range            = tostring(each.value.frontend_port)
  project               = local.project
  target                = google_compute_target_tcp_proxy.api_target_tcp_proxies[each.key].id
}
