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

# The control-plane account may act as each module-created node account: the
# PD CSI controller attaches disks to instances running as them, which needs
# actAs (https://cloud.google.com/compute/docs/access/iam). Scoped per account.
resource "google_service_account_iam_member" "node_service_account_users" {
  for_each = google_service_account.node_service_accounts

  member             = "serviceAccount:${local.control_plane_service_account}"
  role               = "roles/iam.serviceAccountUser"
  service_account_id = "projects/${each.value.project}/serviceAccounts/${local.created_service_account_emails[each.key]}"
}
