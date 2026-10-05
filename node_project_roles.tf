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

# Project roles of the module-created node service accounts: predefined
# roles only, because a deleted custom role's ID cannot be reused for weeks
# (DESIGN.md decision 3). Non-authoritative: other members keep their roles.
resource "google_project_iam_member" "node_project_roles" {
  for_each = merge(
    { for r in var.control_plane_roles : "control-plane ${r}" => { node_role = "control-plane", role = r } if contains(keys(local.created_service_accounts), "control-plane") },
    { for r in var.worker_roles : "worker ${r}" => { node_role = "worker", role = r } if contains(keys(local.created_service_accounts), "worker") },
  )

  member  = "serviceAccount:${local.created_service_account_emails[each.value.node_role]}"
  project = local.project
  role    = each.value.role
}
