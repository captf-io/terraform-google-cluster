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

# Non-contract outputs: ids of what the module created, for operators and for
# the tests' stability checks. The controller never reads them. Alphabetical.

output "api_address_id" {
  description = "ID of the API address (internal or global), or null for a user endpoint."
  value = (
    local.internal_lb ? try(google_compute_address.api_address[0].id, null) :
    local.external_lb ? try(google_compute_global_address.api_global_address[0].id, null) :
    null
  )
}

output "api_backend_service_ids" {
  description = "IDs of the API backend services, by listener."
  value = merge(
    { for k, b in google_compute_region_backend_service.api_region_backend_services : k => b.id },
    { for k, b in google_compute_backend_service.api_backend_services : k => b.id },
  )
}

output "api_forwarding_rule_ids" {
  description = "IDs of the API forwarding rules, by listener."
  value = merge(
    { for k, r in google_compute_forwarding_rule.api_forwarding_rules : k => r.id },
    { for k, r in google_compute_global_forwarding_rule.api_global_forwarding_rules : k => r.id },
  )
}

output "api_instance_group_ids" {
  description = "IDs of the per-zone API instance groups, by zone."
  value       = { for z, g in google_compute_instance_group.api_instance_groups : z => g.id }
}

output "firewall_rule_ids" {
  description = "IDs of the firewall rules, by purpose."
  value = merge(
    { for r in google_compute_firewall.node_internal_firewall : "node_internal" => r.id },
    { for k, r in google_compute_firewall.pod_ingress_firewalls : "pod_ingress_${k}" => r.id },
    { for r in google_compute_firewall.api_ingress_firewall : "api_ingress" => r.id },
  )
}

output "node_service_account_ids" {
  description = "IDs of the module-created node service accounts, by node role."
  value       = { for k, a in google_service_account.node_service_accounts : k => a.id }
}

output "proxy_subnet_cidrs" {
  description = "Ranges of the proxy-only subnets the API firewall rule allows (internal endpoint only)."
  value       = local.proxy_subnet_cidrs
}
