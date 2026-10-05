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

# One service account per node role, unless the user brings one (DESIGN.md
# decision 3). Firewall rules target these accounts, not network tags.
# Service accounts cannot carry labels (README "Tags").
resource "google_service_account" "node_service_accounts" {
  for_each = local.created_service_accounts

  account_id   = each.value
  description  = "${local.description}: ${each.key} nodes"
  display_name = substr("CAPTF ${local.cluster_key} ${each.key}", 0, 100)
  project      = local.project
}
