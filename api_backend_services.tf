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

# Backend services of the external proxy load balancer, one per listener, each
# over every zone's instance group and guarded by the Cloud Armor allowlist
# (DESIGN.md decision 1).
resource "google_compute_backend_service" "api_backend_services" {
  for_each = local.external_lb ? local.api_listeners : {}

  description           = "${local.description}: ${each.value.port_name}"
  health_checks         = [google_compute_health_check.api_health_checks[each.key].id]
  load_balancing_scheme = "EXTERNAL_MANAGED"
  name                  = "${local.name_prefix}-api-${each.value.name}"
  port_name             = each.value.port_name
  project               = local.project
  protocol              = "TCP"
  security_policy       = google_compute_security_policy.api_security_policy[0].id
  # An idle timeout for TCP proxies, 30 seconds by default: long enough for
  # watches and `kubectl logs -f` that stay silent for minutes
  # (https://cloud.google.com/load-balancing/docs/backend-service#timeout-setting).
  timeout_sec = 3600

  dynamic "backend" {
    for_each = google_compute_instance_group.api_instance_groups

    content {
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1
      group           = backend.value.self_link
      max_utilization = 0.8
    }
  }
}
