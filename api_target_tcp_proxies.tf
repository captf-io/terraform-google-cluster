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

# Target TCP proxies of the external load balancer. As with the internal one,
# a proxy lets a control-plane node reach the endpoint it is behind
# (cluster.md "Hairpin reachability").
resource "google_compute_target_tcp_proxy" "api_target_tcp_proxies" {
  for_each = local.external_lb ? local.api_listeners : {}

  backend_service = google_compute_backend_service.api_backend_services[each.key].id
  description     = "${local.description}: ${each.value.port_name}"
  name            = "${local.name_prefix}-api-${each.value.name}"
  project         = local.project
  proxy_header    = "NONE"
}
