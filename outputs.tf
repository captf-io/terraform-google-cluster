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

# Contract outputs of the cluster role, in contract order:
# https://captf.io/docs/module-author/contract/v1alpha1/cluster.html#outputs
# and "health" in https://captf.io/docs/module-author/contract/v1alpha1/common.html

output "control_plane_endpoint" {
  description = "The API endpoint: the user's when given, else the load balancer's address and port, stable for the life of the cluster (cluster.md)."
  value = (
    var.control_plane_endpoint != null ? var.control_plane_endpoint :
    local.api_host != null ? { host = local.api_host, port = local.api_port } :
    null
  )
}

output "failure_domains" {
  description = "One failure domain per zone, all eligible for control-plane machines (cluster.md)."
  value       = [for z in local.zones : { name = z, control_plane = true, attributes = { zone = z } }]
}

output "exports" {
  description = "captf.io/gcp-cluster/v1 exports for machines and pools (README \"Exports\")."
  value       = local.exports
}

output "health" {
  description = "Health of the API load balancer, the cluster's own resource (common.md \"health\")."
  value       = local.health_reading
}
