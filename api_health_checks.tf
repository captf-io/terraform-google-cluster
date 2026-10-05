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

# TCP health checks for the external API load balancer, one per listener;
# TCP goes green with a single backend for both kubeadm and RKE2
# (control-planes/checklist.md "Health checks").
resource "google_compute_health_check" "api_health_checks" {
  for_each = local.external_lb ? local.api_listeners : {}

  check_interval_sec  = 5
  description         = "${local.description}: ${each.value.port_name}"
  healthy_threshold   = 2
  name                = "${local.name_prefix}-api-${each.value.name}"
  project             = local.project
  timeout_sec         = 5
  unhealthy_threshold = 3

  tcp_health_check {
    port = each.value.backend_port
  }
}
