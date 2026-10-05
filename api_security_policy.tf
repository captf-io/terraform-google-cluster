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

# The client allowlist of the public endpoint. Behind a proxy, VPC firewall
# rules see Google's front ends, not clients, so Cloud Armor filters instead
# (https://cloud.google.com/armor/docs/security-policy-overview).
resource "google_compute_security_policy" "api_security_policy" {
  count = local.external_lb ? 1 : 0

  description = "${local.description}: Kubernetes API clients"
  labels      = local.tags
  name        = "${local.name_prefix}-api"
  project     = local.project
  type        = "CLOUD_ARMOR"

  # A basic match condition takes at most 10 ranges, so the allowlist is
  # chunked into rules of 10.
  dynamic "rule" {
    for_each = chunklist(sort(distinct(var.api_allowed_cidrs)), 10)

    content {
      action      = "allow"
      description = "api_allowed_cidrs, part ${rule.key + 1}"
      priority    = 1000 + rule.key

      match {
        versioned_expr = "SRC_IPS_V1"

        config {
          src_ip_ranges = rule.value
        }
      }
    }
  }

  rule {
    action      = "deny(403)"
    description = "Everyone else"
    priority    = 2147483647

    match {
      versioned_expr = "SRC_IPS_V1"

      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
