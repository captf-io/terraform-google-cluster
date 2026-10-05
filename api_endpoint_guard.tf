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

# Records what decides the API endpoint when the load balancer is created, and
# fails any later plan that would change it: CAPI never updates the endpoint,
# and the destructive-plan guard misses in-place changes (CONVENTIONS.md section 12).
resource "terraform_data" "api_endpoint_guard" {
  count = local.module_endpoint ? 1 : 0

  input = merge(local.api_endpoint_inputs, { address = local.api_host })

  lifecycle {
    ignore_changes = [input]

    postcondition {
      condition = length([for k, v in local.api_endpoint_inputs : k if jsonencode(self.input[k]) != jsonencode(v)]) == 0
      error_message = "The API endpoint of this cluster is fixed once its load balancer exists: ${join("; ", [
        for k, v in local.api_endpoint_inputs : "${k} cannot change (recorded ${jsonencode(self.input[k])}, requested ${jsonencode(v)})"
        if jsonencode(self.input[k]) != jsonencode(v)
      ])}. Revert the change, or create a new cluster."
    }
    # A separate check: the address is unknown while its replacement is
    # planned, and an unknown would defer the check above to apply time.
    postcondition {
      condition     = self.input.address == null || local.api_host == null || self.input.address == local.api_host
      error_message = "The API endpoint of this cluster is fixed once its load balancer exists: address cannot change (recorded ${jsonencode(self.input.address)}, now ${jsonencode(local.api_host)}). Revert the change, or create a new cluster."
    }
  }
}
