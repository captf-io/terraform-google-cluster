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

# Cluster health from the cluster's own resources, never from backends, which
# are unhealthy during every control-plane bring-up (CONVENTIONS.md section 10;
# "health" in https://captf.io/docs/module-author/contract/v1alpha1/common.html).
locals {
  # The kube-apiserver forwarding rule's address, read back on every
  # refresh. Null once a refresh finds the rule gone.
  api_forwarding_rule_address = (
    local.internal_lb ? try(google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].ip_address, null) :
    local.external_lb ? try(google_compute_global_forwarding_rule.api_global_forwarding_rules["kube_apiserver"].ip_address, null) :
    null
  )

  health_reading = (
    !local.module_endpoint ? {
      state   = "running"
      healthy = true
      message = "The control-plane endpoint is user-supplied; the cluster owns no load balancer."
      reasons = []
    } :
    local.api_forwarding_rule_address != null ? {
      state   = "running"
      healthy = true
      message = "API forwarding rule serves ${local.api_forwarding_rule_address}:${local.api_port}."
      reasons = []
      } : {
      state   = "terminated"
      healthy = false
      message = "The API forwarding rule ${local.name_prefix}-api-apiserver no longer exists."
      reasons = ["LoadBalancerNotFound"]
    }
  )
}
